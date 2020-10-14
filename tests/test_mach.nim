# Copyright (C) 2020 João Marques Gomes
import os
import strutils
import parsecfg
import unittest
import db_mysql

import mach

const testConfig = "/test_localhost.cfg"

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
        server_fs_home = dict.getSectionValue("Server", "home")
        server_randomize = dict.getSectionValue("Server", "randomize").parseBool

    # randomize must be off for testing
    check server_randomize == false

    # api
    var conn: DbConn = db_mysql.open(db_connection, db_user, db_password, db_schema)
    var api = Api(conn: conn)

    # remove home directory prior to test
    os.removeDir(server_fs_home)

    setup:
      # run before each test
      discard
      
    teardown:
      # run after each test
      discard

    test "create and set home directory":
      check api.createFsHome(server_fs_home) == true      
      api = api.setFsHome(server_fs_home)      
      check api.getFsHome() == server_fs_home      

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

    test "save file in Jerry":
        let jerry = api.getTenant("Jerry")
        os.copyFile("./tests/abc.txt", "./tests/abc_jerry.txt")
        check api.saveFileInTenant(jerry, "./tests/abc_jerry.txt", "bundle1") == true

    test "delete Jerry":
        check api.deleteTenant(1) == true

    test "no tenants after delete":
      let tenants = api.getTenants()
      check tenants.len == 0

    echo "Teardown Api test suite"

    # close the api database connection
    api.conn.close()
    
    # remove home directory after tests
    os.removeDir(server_fs_home)    