local utils = dofile("/etc/nginx/scripts/utils.lua")
local resty_consul = require('resty.consul')

local consul = resty_consul:new({
        host = os.getenv('CONSUL_SERVER'),
        port = 8500
    })

if utils.lookup_location("blacklist_clients", ngx.var.remote_addr, nil) then
    ngx.log(ngx.DEBUG, ngx.var.remote_addr .. " is in blacklisted clients. Responding with 405")
    ngx.exit(ngx.HTTP_NOT_ALLOWED)
end

local host = ngx.req.get_headers()["Host"]
if not host then
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
end
ngx.log(ngx.DEBUG, "Got request for host: " .. host)

if utils.lookup_location("blacklist_hosts", host, nil) then
    ngx.log(ngx.DEBUG, host .. " is in blacklisted hosts. Responding with 405")
    ngx.exit(ngx.HTTP_NOT_ALLOWED)
end

ngx.req.read_body()

local settings = ngx.shared.settings;

ngx.log(ngx.DEBUG, "Will lookup: servers:" .. host .. " in Redis")
locations = utils.lookup_location("servers",host,nil)
if not locations then
    ngx.log(ngx.INFO, "Not found in Redis: " .. host .. ", will look it up in consul")

    -- check if host is public
    local pub,err = consul:get('/kv/public/' .. host)
    if not pub then
      utils.store_location("servers",host,1,"false")
      ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end

    -- get registered endpoints for host
    local res,err = consul:get('/catalog/service/' .. host)
    if res == nil  then
        ngx.log(ngx.ERR, "ERROR: " .. err)
    end
    if type(res) == 'table' then
      -- utils.print(res)
      utils.store_location("servers",host,1,res)
      locations = res
    else
        ngx.log(ngx.ERR, "Failed to decode value :(")
        utils.store_location("servers",host,1,"false")
        ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end
end

-- utils.print(locations)

if locations == "false" then
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
end

-- pick a random host
local i = math.random( #locations )
local location = locations[i]

if location then
    forward_location = "http://" .. location["Address"] .. ":" .. location["ServicePort"]
else
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
end

if forward_location then
    ngx.log(ngx.INFO, "forward_location: "..forward_location)
    res = utils.forward(forward_location..ngx.var.request_uri)
    utils.send_response(res)
end
