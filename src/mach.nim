import asyncdispatch

import jester # jester webserver
import db_mysql # Nim MySQL client 
# import logging   # Logging utils
import os # arguments parsing
import parsecfg # handle CFG (config) files
import strutils # string basic functions
import json # parse json
import times # Nim date/time module
import re

import machpkg/auth

const defaultConfig = "/config/dev_localhost.cfg"

type
    ## General mach server Api error
    ApiError* = object of CatchableError

    ## Mach server API
    Api* = object
        dbParameters*: DbParameters
        home: string
        salt*: string
        corsDomain*: string

    ## Mach server DbConn parameters
    DbParameters* = object
        connection*: string
        user*: string
        password*: string
        schema*: string

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

proc getConn*(api: Api): DbConn {.raises: [DbError, ValueError].} =

    return db_mysql.open(api.dbParameters.connection
        , api.dbParameters.user
        , api.dbParameters.password
        , api.dbParameters.schema)

proc getTenants*(api: Api): seq[Tenant] {.raises: [ApiError].} =
    ## Return all tenant

    try:
        let conn = api.getConn()
        let rows = conn.getAllRows(sql"SELECT id, name, hash FROM tenant")

        var tenants: seq[Tenant] = @[]
        for row in rows:
            let tenant: Tenant = Tenant(
                id: uint16(row[0].parseUInt)
                , name: row[1]
                , hash: row[2])            

            tenants.add(tenant)
        
        conn.close()
        return tenants

    except DbError, ValueError:
        echoAndRaiseException("Error getting tenants", ApiError)    

proc getTenant*(api: Api, id: uint16): Tenant {.raises: [ApiError].} =
    ## Return tenant by id

    try:
        let conn = api.getConn()
        let row = conn.getRow(sql"SELECT id, name, hash FROM tenant where id = ?", id)

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
        let conn = api.getConn()
        let row = conn.getRow(sql"SELECT id, name, hash FROM tenant where name = ?", name)
        conn.close()

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
        
        let conn = api.getConn()
        let hash = auth.makeSha256Hash(name, api.salt)        
        conn.exec(sql"INSERT INTO tenant (name, hash) VALUES (?, ?)", name, hash)
        let id: uint = conn.getRow(sql"SELECT LAST_INSERT_ID()")[0].parseUInt

        let 
            instanceHome = api.getFsHome()            
            tenantHome = os.joinPath(instanceHome, (hash)[0..3])
        os.createDir(tenantHome)

        conn.close()
        return id

    except DbError, ValueError, IOError, OSError:
        echoAndRaiseException("Error creating tenant", ApiError)

proc deleteTenant*(api: Api, id: uint): bool =
    ## Deletes a tenant by id
    ## Removes from the mach database and
    ## clears it's tenant directory from the file system/store
    ## returns true if tenant was successfully deleted and false otherwise

    try:
        let conn = api.getConn()
        let affectedRows = conn.execAffectedRows(
                sql"DELETE FROM tenant WHERE id = ?", id)

        conn.close()
        return affectedRows > 0

    except DbError:
        echoException("Error deleting tenant")

        return false

proc updateTenant*(api: Api, id: uint16, name: string): bool =
    ## Update tenant attributes
    ## returns true if tenant was successfully updated and false otherwise

    try:
        let conn = api.getConn()
        let affectedRows = conn.execAffectedRows(sql"UPDATE tenant SET name = ? WHERE id = ?"
        , name, id)

        conn.close()
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

proc isOriginValid*(api: Api, headers: HttpHeaders): bool =
    # Check if the HTTP Origin is valid under the CORS domain setting

    let corsDomain: string = api.corsDomain

    # if the we accept requests from anywhere, *, all origins are valid
    if corsDomain == "*":
        return true

    # otherwise we need to check the HTTP request origin 
    # if it exists and it's equal to the configured corsDomain
    # then the origin is valid
    if headers.hasKey("origin"):
        if corsDomain == headers["origin"]:
            return true

    # if we reach this point the origin is not valid
    return false

proc getJsonHeaders*(api: Api): any =
    # Return default JSON headers

    return {"Access-Control-Allow-Origin": api.corsDomain, "Content-Type": "application/json"}

var api: Api

router web:    

    # GET ping the service
    get "/":
        resp "It's alive!"

    # GET return all tenants
    get "/tenant":
        
        try:
            let tenants = api.getTenants()
            resp(Http200, headers=api.getJsonHeaders(), $(%*tenants))

        except ApiError as e:
            resp(Http404, headers=api.getJsonHeaders(), $(%*{"msg": e.msg}))

    # GET return tenant
    get "/tenant/@id":
        cond re.match(@"id", re"^\d+$")

        if not(api.isOriginValid(request.headers)):
            resp(Http403, headers={"Content-Type": "application/json"}
            , $(%*{"msg": "Invalid origin!"}))

        try:
            let tenant = api.getTenant(uint16(@"id".parseUInt))
            resp(Http200, headers=api.getJsonHeaders(), $(%*tenant))

        except ApiError as e:
            resp(Http404, headers=api.getJsonHeaders(), $(%*{"msg": e.msg}))
        
    # GET return tenant
    get "/tenant/@name":
        cond re.match(@"name", re"^\S+$")

        if not(api.isOriginValid(request.headers)):
            resp(Http403, headers={"Content-Type": "application/json"}
            , $(%*{"msg": "Invalid origin!"}))

        try:
            let tenant = api.getTenant(@"name")
            resp(Http200, headers=api.getJsonHeaders(), $(%*tenant))

        except ApiError as e:
            resp(Http404, headers=api.getJsonHeaders(), $(%*{"msg": e.msg}))

   # OPTIONS 
    options "/tenant":
                       
        resp(Http204, headers={"Access-Control-Allow-Origin": api.corsDomain, "Access-Control-Allow-Methods": "POST", "Access-Control-Allow-Headers": "content-type"}, "")

    # POST create new tenant
    post "/tenant":
        let
            payload: JsonNode = request.body.parseJson
            name: string = payload["name"].getStr

        if not(api.isOriginValid(request.headers)):
            resp(Http403, headers={"Content-Type": "application/json"}, $(%*{"msg": "Invalid origin!"}))

        try:
            let id = api.createTenant(name)
            resp(Http200, headers=api.getJsonHeaders(), $(%*{"msg": "Tenant created", "id": id}))
            
        except ApiError:
            resp(Http500, headers=api.getJsonHeaders(), $(%*{"msg": "Error creating tenant!"}))        

    # OPTIONS 
    options "/tenant/@id/@name?":
        cond re.match(@"id", re"^\d+$")
                
        resp(Http204, headers={"Access-Control-Allow-Origin": api.corsDomain, "Access-Control-Allow-Methods": "DELETE, PUT", "Access-Control-Allow-Headers": "content-type"}, "")

    # DELETE a tenant
    delete "/tenant/@id/@name":
        cond re.match(@"id", re"^\d+$") and re.match(@"name", re"^\S+$")

        if not(api.isOriginValid(request.headers)):
            resp(Http403, headers={"Content-Type": "application/json"}, $(%*{"msg": "Invalid origin!"}))

        # get tenant and check the name matches
        let id: uint16 = uint16(@"id".parseUInt)
        try:
            let tenant = api.getTenant(id)
            if tenant.name != @"name":
                resp(Http500, headers=api.getJsonHeaders(), $(%*{"msg": "Error, name doesn't match tenant"}))

        except ApiError as e:
            resp(Http404, headers=api.getJsonHeaders(), $(%*{"msg": e.msg}))

        try:
            if api.deleteTenant(id):
                resp(Http200, headers=api.getJsonHeaders(), $(%*{"msg": "Tenant deleted"}))
                
            else:
                resp(Http404, headers=api.getJsonHeaders(), $(%*{"msg": "Tenant not found"}))

        except ApiError:
            resp(Http500, headers=api.getJsonHeaders(), $(%*{"msg": "Error deleting tenant"}))


    # PUT update tenant details
    put "/tenant/@id":
        cond re.match(@"id", re"^\d+$")

        if not(api.isOriginValid(request.headers)):
            resp(Http403, headers={"Content-Type": "application/json"}
            , $(%*{"msg": "Invalid origin!"}))

        let
            payload: JsonNode = request.body.parseJson
            id: uint16 = uint16(payload["id"].getInt)
            name: string = payload["name"].getStr

        try:
            if api.updateTenant(id, name):
                resp(Http200, headers=api.getJsonHeaders(), $(%*{"msg": "Tenant updated"}))
            else:
                resp(Http200, headers=api.getJsonHeaders(), $(%*{"msg": "No change to tenant"}))
                

        except ApiError:
            resp(Http500, headers=api.getJsonHeaders(), $(%*{"msg": "Error updating tenant"}))

    # UPLOAD file to tenant
    post "/tenant/@name/upload":
        ## Handles multipart POST request
        ## Stores the tenant files

        if not(api.isOriginValid(request.headers)):
            resp(Http403, headers={"Content-Type": "application/json"}
            , $(%*{"msg": "Invalid origin!"}))

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
        server_corsDomain = dict.getSectionValue("Server", "corsDomain")        

    # db 
    let dbPars: DbParameters = DbParameters(
        connection: db_connection
        , user: db_user
        , password: db_password
        , schema: db_schema)

    # create salt
    let webSalt = if server_randomize:
            auth.makeSalt()
        else:
            "fixedSaltForTesting"

    # api    
    api = Api(dbParameters: dbPars, salt: webSalt, corsDomain: server_corsDomain)

    # create the instance file system home
    discard api.createFsHome(server_fs_home)
    api = api.setFsHome(server_fs_home)

    # web
    let settings = newSettings(bindAddr = server_url, port = server_port)    
    var jester = initJester(web, settings)

    jester.serve()

when isMainModule:
    main()
