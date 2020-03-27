# Copyright (C) 2020 João Marques Gomes
import os
import parsecfg
import unittest
import db_mysql

import mach

const testConfig = "./test_localhost.cfg"

suite "March server Api test suite":
    echo "Setup Api test suite"

    # reset the test schema
    discard execShellCmd("""mysql -hlocalhost -P3306 -uroot -ppandora -e"source ./tests/0_mach_user.sql;"""")
    discard execShellCmd("""mysql -hlocalhost -P3306 -umach_test -pmach_test123 mach_test -e"source ./tests/1_mach_schema.sql;"""")

    var dict: Config
    dict = loadConfig(getAppDir() & testConfig)
    echo "Using test configuration ", testConfig

    let
        db_connection = dict.getSectionValue("Database", "connection")
        db_user = dict.getSectionValue("Database", "user")
        db_password = dict.getSectionValue("Database", "password")
        db_schema = dict.getSectionValue("Database", "schema")
        # server_url = dict.getSectionValue("Server", "url")
        # server_port = dict.getSectionValue("Server", "port").parseUInt.Port

    # api
    var conn: DbConn = db_mysql.open(db_connection, db_user, db_password, db_schema)
    var api = Api(conn: conn)

    setup:
      # run before each test
      discard
      
    teardown:
      # run after each test
      discard
    
    test "no tenants":
      let tenants = api.getTenants()
      check tenants.len == 0

    test "create tenant Tom":
        let tom_id = api.createTenant("Tom")
        check tom_id == 1

    test "get Tom":
        let tom = api.getTenant("Tom")
        check tom.name == "Tom"

    test "change Tom name to Jerry":
        check api.updateTenant(1, "Jerry") == true
        let jerry = api.getTenant("Jerry")
        check jerry.name == "Jerry"

    test "delete Jerry":
        check api.deleteTenant(1) == true

    test "no tenants after delete":
      let tenants = api.getTenants()
      check tenants.len == 0

    echo "Teardown Api test suite"
    api.conn.close()