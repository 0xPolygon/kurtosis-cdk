{{range .dbs}}
    \connect {{$.master_db}} {{$.master_user}};
    CREATE USER {{.user}} with password '{{.password}}';
    CREATE DATABASE {{.name}} OWNER {{.user}};
    {{if .init}}
        \connect {{.name}} {{.user}};
        {{.init}}
    {{end}}
    grant all privileges on database {{.name}} to {{.user}};
{{end}}
