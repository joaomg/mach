import asyncdispatch

import jester # jester webserver
import db_mysql # Nim MySQL client 
# import logging   # Logging utils
import os # arguments parsing
import parsecfg # handle CFG (config) files
import strutils # string basic functions
import json # parse json
import times # Nim date/time module
import random
import re

import machpkg/auth

const defaultConfig = "/config/dev_localhost.cfg"

type
    ## General mach server Api error
    ApiError* = object of CatchableError

    ## Mach server API
    Api* = object
        conn*: DbConn
        home: string

    ## Mach tenant
    ## identified by name and handled internally in Mach by id and hash
    ## the api external methods should accept the tenant name
    Tenant* = object
        id*: uint16
        name*: string
        hash*: string
        hashShort*: string

proc echoException(userMsg: string) =
    ## Outputs user and exception messages

    let exMsg = getCurrentExceptionMsg()
    echo userMsg, ": ", exMsg

proc echoAndRaiseException(userMsg: string, e: typedesc) =
    ## Outputs user and exception messages
    ## and raises the exception e

    let exMsg = getCurrentExceptionMsg()
    let ex = getCurrentException()
    echo userMsg, "; ", ex.name, ": ", exMsg
    raise newException(e, userMsg)

proc createFsHome*(api:Api, server_fs_home: string):bool =
    ## Create file system home if it doesn't exit    

    # create mach instance home directory
    os.createDir(server_fs_home)

    # return if home directory exists
    return os.existsDir(server_fs_home)

proc setFsHome*(api: Api, server_fs_home: string):Api =
    ## Define the instance file system home
    
    var changedApi: Api = api
    changedApi.home = server_fs_home
    return changedApi

proc getFsHome*(api: Api):string =
    ## Returns the instance file system home
    
    return api.home

proc getTenants*(api: Api): seq[Tenant] {.raises: [ApiError].} =
    ## Return all tenant

    try:
        let rows = api.conn.getAllRows(sql"SELECT id, name, hash FROM tenant")

        var tenants: seq[Tenant] = @[]
        for row in rows:
            let tenant: Tenant = Tenant(
                id: uint16(row[0].parseUInt)
                , name: row[1]
                , hash: row[2])            

            tenants.add(tenant)
            
        return tenants

    except DbError, ValueError:
        echoAndRaiseException("Error getting tenants", ApiError)

proc getTenant*(api: Api, id: uint16): Tenant {.raises: [ApiError].} =
    ## Return tenant by id

    try:
        let row = api.conn.getRow(sql"SELECT id, name, hash FROM tenant where id = ?", id)

        if row[0] == "":
            raise newException(ApiError, "Tenant not found")
        else:
            let tenant: Tenant = Tenant(
                id: uint16(row[0].parseUInt)
                , name: row[1]
                , hash: row[2])                
            return tenant

    except DbError, ValueError:
        echoAndRaiseException("Error getting tenant", ApiError)

proc getTenant*(api: Api, name: string): Tenant {.raises: [ApiError].} =
    ## Return tenant by name

    try:
        let row = api.conn.getRow(sql"SELECT id, name, hash FROM tenant where name = ?", name)

        if row[0] == "":
            raise newException(ApiError, "Tenant not found")
        else:
            let tenant: Tenant = Tenant(
                id: uint16(row[0].parseUInt)
                , name: row[1]
                , hash: row[2])
            return(tenant)

    except DbError, ValueError:
        echoAndRaiseException("Error getting tenant", ApiError)

proc createTenant*(api: Api, name: string): uint {.raises: [ApiError].} =
    ## Create a new tenant
    ## returns tenant id

    try:
        let hash = auth.makeSha256Hash(name)
        api.conn.exec(sql"INSERT INTO tenant (name, hash) VALUES (?, ?)", name, hash)
        let id: uint = api.conn.getRow(sql"SELECT LAST_INSERT_ID()")[0].parseUInt

        let 
            instanceHome = api.getFsHome()            
            tenantHome = os.joinPath(instanceHome, (hash)[0..3])
        os.createDir(tenantHome)

        return id

    except DbError, ValueError, IOError, OSError:
        echoAndRaiseException("Error creating tenant", ApiError)

proc deleteTenant*(api: Api, id: uint): bool =
    ## Deletes a tenant by id
    ## Removes from the mach database and
    ## clears it's tenant directory from the file system/store
    ## returns true if tenant was successfully deleted and false otherwise

    try:
        let affectedRows = api.conn.execAffectedRows(
                sql"DELETE FROM tenant WHERE id = ?", id)

        return affectedRows > 0

    except DbError:
        echoException("Error deleting tenant")

        return false

proc updateTenant*(api: Api, id: uint16, name: string): bool =
    ## Update tenant attributes
    ## returns true if tenant was successfully updated and false otherwise

    try:
        let affectedRows = api.conn.execAffectedRows(sql"UPDATE tenant SET name = ? WHERE id = ?"
        , name, id)

        return affectedRows > 0

    except DbError:
        echoException("Error updating tenant")

        return false

proc saveFileInTenant*(api: Api, tenant: Tenant, source: string, bundle: string = ""): bool =
    ## Place file in tenant file system home
    ## Optionally inside a bundle sub-directory    

    let 
        instanceHome = api.getFsHome()
        tenantHome = os.joinPath(instanceHome, tenant.hash[0..3])
        fileName = os.extractFilename(source)        
        destination = os.joinPath(tenantHome, bundle, fileName)
        
    try: 
        os.createDir(os.joinPath(tenantHome, bundle))
        os.moveFile(source, destination)
        return true
    except OSError:
        echoException("Error moving file to tenant")
        return false

var api: Api
var conn: DbConn

router web:
    # GET ping the service
    get "/":
        resp "It's alive!"

    # GET return tenant
    get "/tenant/@id":
        cond re.match(@"id", re"^\d+$")

        try:
            let tenant = api.getTenant(uint16(@"id".parseUInt))
            resp(Http200, $(%*tenant),
                contentType = "application/json")

        except ApiError as e:
            resp(Http404, $(%*{"msg": e.msg}),
                contentType = "application/json")
        

    # GET return tenant
    get "/tenant/@name":
        cond re.match(@"name", re"^\S+$")

        try:
            let tenant = api.getTenant(@"name")
            resp(Http200, $(%*tenant),
                contentType = "application/json")

        except ApiError as e:
            resp(Http404, $(%*{"msg": e.msg}),
                contentType = "application/json")

    # POST create new tenant
    post "/tenant":
        let
            payload: JsonNode = request.body.parseJson
            name: string = payload["name"].getStr

        try:
            let id = api.createTenant(name)
            resp(Http200, $(%*{"msg": "Tenant created", "id": id}),
                    contentType = "application/json")

        except ApiError:
            resp(Http500, $(%*{"msg": "Error creating tenant"}),
                    contentType = "application/json")

    # DELETE a tenant
    delete "/tenant/@id":
        cond re.match(@"id", re"^\d+$")

        let id: uint = @"id".parseUInt

        try:
            if api.deleteTenant(id):
                resp(Http200, $(%*{"msg": "Tenant deleted"}),
                        contentType = "application/json")
            else:
                resp(Http404, $(%*{"msg": "Tenant not found"}),
                        contentType = "application/json")

        except ApiError:
            resp(Http500, $(%*{"msg": "Error deleting tenant"}),
                    contentType = "application/json")

    # PUT update tenant details
    put "/tenant/@id":        
        cond re.match(@"id", re"^\d+$")

        let
            payload: JsonNode = request.body.parseJson
            id: uint16 = uint16(payload["id"].getInt)
            name: string = payload["name"].getStr

        try:
            if api.updateTenant(id, name):
                resp(Http200, $(%*{"msg": "Tenant updated"})
                , contentType = "application/json")
            else:
                resp(Http404, $(%*{"msg": "Tenant not found or nothing to update"})
                , contentType = "application/json")

        except ApiError:
            resp(Http500, $(%*{"msg": "Error updating tenant"})
            , contentType = "application/json")

    # UPLOAD file to tenant
    post "/tenant/@name/upload":
        ## Handles multipart POST request
        ## Stores the tenant files

        cond re.match(@"name", re"^\S+$")

        var fileCount: int = 0                                      # number of handled files
        let bundle: string = makeSha256Hash(@"name")                # used to pack files together for ETL tasks\jobs
        let tmpDir: string = os.joinPath(api.getFsHome, bundle)     # create a temporary directory and place uploaded files there
        
        try:
            let tenant = api.getTenant(@"name")

            os.createDir(tmpDir)   

            for name, value in request.formData.pairs:
                if name == "files":
                    let fileName = value.fields["filename"]                    
                    let tmpFile = os.joinPath(tmpDir, fileName)                    
                    writeFile(tmpFile, value.body)
                    discard api.saveFileInTenant(tenant, tmpFile, bundle)

                    inc fileCount

            os.removeDir(tmpDir)

        except ApiError as e:

            os.removeDir(tmpDir)

            resp(Http404, $(%*{"msg": e.msg}),
                contentType = "application/json")        

        resp(Http200, $(%*{"msg": "Received " & $fileCount & " files"}), 
                contentType = "application/json")


proc main() =

    # configuration
    var dict: Config
    if paramCount() > 0:        
        # param
        let paramFile = paramStr(1)
        echo "Fetching configuration from ", paramFile        
        dict = loadConfig(paramFile)
        echo "Using configuration ", paramFile

    else:
        # load default configuration file:
        dict = loadConfig(getAppDir() & defaultConfig)
        echo "Using default configuration ", defaultConfig

    let
        db_connection = dict.getSectionValue("Database", "connection")
        db_user = dict.getSectionValue("Database", "user")
        db_password = dict.getSectionValue("Database", "password")
        db_schema = dict.getSectionValue("Database", "schema")
        server_url = dict.getSectionValue("Server", "url")
        server_port = dict.getSectionValue("Server", "port").parseUInt.Port
        server_fs_home = dict.getSectionValue("Server", "home")
        server_randomize = dict.getSectionValue("Server", "randomize").parseBool

    # do a random.randomize call
    if server_randomize:
        let seed: int64 = times.getTime().toUnix    
        random.randomize(seed)    

    # api
    conn = db_mysql.open(db_connection, db_user, db_password, db_schema)
    api = Api(conn: conn)

    # create the instance file system home
    discard api.createFsHome(server_fs_home)
    api = api.setFsHome(server_fs_home)

    # web
    let settings = newSettings(bindAddr = server_url, port = server_port)
    var jester = initJester(web, settings)

    jester.serve()

when isMainModule:
    main()
