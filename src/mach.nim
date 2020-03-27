# start jester server in port 5100
# nim c -r .\server.nim 5100
import asyncdispatch

import jester # jester webserver
import db_mysql # Nim MySQL client 
# import logging   # Logging utils
import os # arguments parsing
import parsecfg # handle CFG (config) files
import strutils # string basic functions
import json # parse json
import std/sha1 # Nim md5 implementation

const defaultConfig = "/../config/dev_localhost.cfg"

type
    ## General mach server Api error
    ApiError* = object of Exception

    ## Mach server API
    Api* = object
        conn*: DbConn

    ## Mach tenant
    ## identified by name and handled internally in Mach by id and hash
    ## the api external methods should accept the tenant name
    Tenant* = object
        id*: uint16
        name*: string
        hash*: string

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
        let hash: SecureHash = secureHash(name)
        api.conn.exec(sql"INSERT INTO tenant (name, hash) VALUES (?, ?)", name, hash)
        let id: uint = api.conn.getRow(sql"SELECT LAST_INSERT_ID()")[0].parseUInt
        return id

    except DbError, ValueError:
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

var api: Api
var conn: DbConn

router web:
    # GET ping the service
    get "/":
        resp "It's alive!"

    # GET return tenant
    get "/tenant/@id":
        cond @"id".isDigit

        try:
            let tenant = api.getTenant(uint16(@"id".parseUInt))
            resp(Http200, $(%*tenant),
                contentType = "application/json")

        except ApiError as e:
            resp(Http404, $(%*{"msg": e.msg}),
                contentType = "application/json")

    # GET return tenant
    get "/tenant/@name":
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

        except ApiError as e:
            resp(Http500, $(%*{"msg": "Error creating tenant"}),
                    contentType = "application/json")

    # DELETE a tenant
    delete "/tenant/@id":
        cond @"id".isDigit

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
        cond @"id".isDigit

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
        resp(Http200, $(%*{"msg": "file(s) upload to " & @"name"})
        , contentType = "application/json")

proc main() =

    # configuration
    var dict: Config
    if paramCount() > 0:
        # param
        let paramFile = paramStr(1)
        echo paramFile
        dict = loadConfig(paramFile)
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

    # api
    conn = db_mysql.open(db_connection, db_user, db_password, db_schema)
    api = Api(conn: conn)

    # web
    let settings = newSettings(bindAddr = server_url, port = server_port)
    var jester = initJester(web, settings)

    jester.serve()

when isMainModule:
    main()
