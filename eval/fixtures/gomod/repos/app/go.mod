// Façade over the shared libraries.
module example.com/app

go 1.22

toolchain go1.22.4

require (
	example.com/lib v1.4.0
	example.com/log v0.3.1 // indirect
	golang.org/x/text v0.14.0
	"example.com/cli" v1.0.0
)

replace example.com/log => ../log-fork
