# mach
A MACHine originated data processing system



#### go to mach server development home directory
cd c:\joaomg\mach

### install depedencies
nimble install --depsOnly

### run tests
nimble test

### build mach
nimble build

#### create mach user and schema
mysql -hlocalhost -P3306 -uroot -ppandora -e"source config/0_mach_user.sql;"
mysql -hlocalhost -P3306 -umach_dev -pmach_dev123 mach_dev -e"source config/1_mach_schema.sql;"

#### start mach jester server using development configuration
nimble run mach config/dev_localhost.cfg

#### get Jerry tenant details
curl localhost:5100/tenant/Jerry

#### create tenant Tom
curl -X POST -H "Content-Type: application/json" -d "{\"name\":\"Tom\"}" localhost:5100/tenant

#### get tenant 2
curl localhost:5100/tenant/2

#### update tenant 2, change name from tom to jerry
curl -X PUT -H "Content-Type: application/json" -d "{\"id\":2, \"name\":\"Jerry\"}" localhost:5100/tenant/2

#### upload files to tenant jerry
curl -X POST -F files=@tests/1.txt -F files=@tests/2.txt localhost:5100/tenant/jerry/upload

#### delete tenant 1
curl -X DELETE localhost:5100/tenant/1



### Visual Studio Code tips
To build and run current nim file press F6 (using the Nim 0.6.6 extension)



### Windows 10 Powershell tips
Remove the Powershell alias to curl. 
By default the curl command in Powershell is redirected to Invoke-WebRequest. Which has completely different sintax from curl.
Deleting the alias enables us to use the original curl command (if installed and set in PATH) from Powershell. 
https://superuser.com/questions/883914/how-do-i-permanently-remove-a-default-powershell-alias
