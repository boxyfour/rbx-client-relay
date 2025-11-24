# rbx-client-relay

a relay(?) server for roblox

## features

* can recieve global commands to roblox servers
* can recieve server-specific commands, only the server will run it
* has basic authentication

## prerequisites

* install roblox studio
* (optional) install [rojo](https://rojo.space/docs/v7/)

## usage

make sure you have [rblx-relay](https://github.com/boxyfour/rbx-relay) server set up. either grab a model from [releases](https://github.com/boxyfour/rbx-relay/releases) or download the source code, and using rojo, sync your project into roblox studio

then, fill in the following fields for your relay to work correctly
	* ip_address
	* port
	* secret

port is usually 5000 unless you've modified the server config

init.server.luau describes how you implement a "topic". have fun!

# todo

* bugtest