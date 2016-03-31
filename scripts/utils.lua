local cjson = require('cjson')

local utils = {}

local redis_server = os.getenv('REDIS_SERVER')

utils.get_method = function(req)
  local ngx_methods = {
    ["GET"] = ngx.HTTP_GET,
    ["HEAD"] = ngx.HTTP_HEAD,
    ["PUT"] = ngx.HTTP_PUT,
    ["POST"] = ngx.HTTP_POST,
    ["DELETE"] = ngx.HTTP_DELETE,
    ["OPTIONS"] = ngx.HTTP_OPTIONS
  }
  return ngx_methods[req.get_method()]
end

utils.send_response = function(res)
  ngx.status = res.status
  for k, v in pairs(res.header) do
    ngx.header[k] = v
  end
  ngx.print(res.body)
end

utils.forward = function(location)
  return ngx.location.capture("/proxy", {
    args = {upstream = location},
    always_forward_body = true,
    share_all_vars = true,
    method = utils.get_method(ngx.req)
  })
end

utils.lookup_location = function(type,key,default)
  local redis = require "resty.redis"
  local red = redis:new()
  local ok, err = red:connect(redis_server, 6379)
  if ok then
    local location, err = red:get(type..":"..key)
    local ok, err = red:set_keepalive(0, 128)
    if not ok then
      ngx.log(ngx.ERR,"redis:set_keepalive failed", err)
    end
    if location ~= ngx.null then
      return cjson.decode(location)
    end
  else
    ngx.log(ngx.ERR,"redis:connect failed"..err)
  end
  return default
end

utils.store_location = function(type,key,timeout,location)
  local data = cjson.encode(location)
  local redis = require "resty.redis"
  local red = redis:new()
  local ok, err = red:connect(redis_server, 6379)
  if ok then
    if timeout == 0 then
      ok, err = red:set(type..":"..key, data)
    else
      ok, err = red:setex(type..":"..key, timeout, data)
    end
    if not ok then
      ngx.log(ngx.ERR,"redis:set failed", err)
    end
    local ok, err = red:set_keepalive(0, 128)
    if not ok then
      ngx.log(ngx.ERR,"redis:set_keepalive failed", err)
    end
  else
    ngx.log(ngx.ERR,"redis:connect failed"..err)
  end
end

utils.increment = function(type,key)
  local redis = require "resty.redis"
  local red = redis:new()
  local ok, err = red:connect(redis_server, 6379)
  if ok then
    ok, err = red:incr(type..":"..key)
    if not ok then
      ngx.log(ngx.ERR,"redis:incr failed", err)
    end
    local ok, err = red:set_keepalive(0, 128)
    if not ok then
      ngx.log(ngx.ERR,"redis:set_keepalive failed", err)
    end
  else
    ngx.log(ngx.ERR,"redis:connect failed"..err)
  end
end

utils.delete = function(type,key)
  local redis = require "resty.redis"
  local red = redis:new()
  local ok, err = red:connect(redis_server, 6379)
  if ok then
    ok, err = red:del(type..":"..key)
    if not ok then
      ngx.log(ngx.ERR,"redis:del failed", err)
    end
    local ok, err = red:set_keepalive(0, 128)
    if not ok then
      ngx.log(ngx.ERR,"redis:set_keepalive failed", err)
    end
  else
    ngx.log(ngx.ERR,"redis:connect failed"..err)
  end
end

utils.print = function(data)
  if type(data) == 'table' then
    for k, v in pairs(data) do
      if type(v) == 'table' then
        utils.print(v)
      else
        ngx.log(ngx.DEBUG, k .. ": " .. tostring(v))
      end
    end
  else
    ngx.log(ngx.DEBUG, data)
  end
end

return utils
