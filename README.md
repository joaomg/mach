# mach
MACHine for data processing.

A Nim REST backend service with CORS.

Using a MySQL\MariaDB relational database for data storage.

Take a look at https://github.com/joaomg/machui fronted (in Next.js).

## Development

### Clone mach and enter directory
```bash
git clone https://github.com/joaomg/mach.git

cd mach
```

### Install depedencies
```bash
nimble install --depsOnly
```

### Run tests
```bash
nimble test
```

### Build mach
```bash
nimble build
```

## Usage

### Create mach user and schema
```bash
mysql -hlocalhost -P3306 -uroot -ppandora -e"source config/0_mach_user.sql;"

mysql -hlocalhost -P3306 -umach_dev -pmach_dev123 mach_dev -e"source config/1_mach_schema.sql;"
```

### Start mach jester server using development configuration
```bash
nimble run mach config/dev_localhost.cfg
```

### Use the API/webservice with curl 

- get Jerry tenant details
```bash
curl localhost:5100/tenant/Jerry
```

- create tenant Tom
```bash
curl -X POST -H "Content-Type: application/json" -d "{\"name\":\"Tom\"}" localhost:5100/tenant
```

- get tenant 2
```bash
curl localhost:5100/tenant/2
```

- update tenant 2, change name from tom to jerry
```bash
curl -X PUT -H "Content-Type: application/json" -d "{\"id\":2, \"name\":\"Jerry\"}" localhost:5100/tenant/2
```

- upload files to tenant jerry
```bash
curl -X POST -F files=@tests/1.txt -F files=@tests/2.txt localhost:5100/tenant/jerry/upload
```

- delete tenant 1
```bash
curl -X DELETE localhost:5100/tenant/1
```

- if the corsDomain parameter is set the Origin Header must defined accordingly
```bash
curl -H "Origin: http://localhost:3000" localhost:5100/tenant
```

## Environment 

I'm using Visual Studio Code, in a Ubuntu  Linux, and the excelent Nim extension (v0.6.6) by Konstantin Zaitsev.

The code is manged in git (github). 

### Nim in Visual Studio Code
To build and run current nim file press F6 (using the Nim 0.6.6 extension).

### cURL in Windows 10 Powershell
Remove the Powershell alias to curl. 

By default the curl command in Powershell is redirected to Invoke-WebRequest. Which has completely different sintax from curl.

Deleting the alias enables us to use the original curl command (if installed and set in PATH) from Powershell. 

https://superuser.com/questions/883914/how-do-i-permanently-remove-a-default-powershell-alias
