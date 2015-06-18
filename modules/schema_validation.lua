local xml = require("xml")
local api = require("api_loader")
local mob_types = api.init("data/HMI_API.xml")
local hmi_types = api.init("data/MOBILE_API.xml")

if (not hmi_api) then  hmi_api = xml.open("data/HMI_API.xml") end
if (not mobile_api) then mobile_api = xml.open("data/MOBILE_API.xml") end

-- ToDo: Fix me. detail: APPLINK-13219

local module = {
                mt = {__index = { } },
                        api_type= {
                            HMI = 1,
                            MOBILE= 2
                     }
              }

local function dump(o)
   if type(o) == 'table' then
      local s = '{ '
      for k,v in pairs(o) do
         if type(k) ~= 'number' then k = '"'..k..'"' end
         s = s .. '['..k..'] = ' .. dump(v) .. ','
      end
      return s .. '} \n'
   else
      return tostring(o)
   end
end


local function compare(schema,function_id, msgType,user_data, mandatory_check)

  local doc = ''
  local bool_result = true
  local errorMessage = {}
  local types = ''

  local function get_xml_shema_validation(doc,types,name, msg_type)
    local retval= {}
    local class_, short_name
    if (name == nil ) then return retval end
    if (string.find(name, "%.")) then
        class_, short_name = name:match("([^.]+).([^.]+)")  
    else
       class_ ='Ford Sync RAPI'
       short_name = name
    end
     for _, v1 in ipairs(doc:xpath("//param/parent::function[@name='".. short_name .."']" )) do
        if (v1:attr("messagetype") == msg_type and v1:parent():attr("name")== class_) then
          if (type(v1:children() == 'table')) then
            for _, v2 in ipairs(v1:children()) do 
              local class_type = v2:attr('type')
              if(type(v2:attr('name')) ~= 'nil') then
                local tmp = {}
                if ( types.classes[class_type]) then
                  tmp['class'] = string.format("%s",class_type)
                end
                if (types.enum[class_type]) then
                  tmp['class'] = "enum"
                  tmp['type'] = string.format("%s",class_type)
                end
                if (types.struct[class_type]) then
                  tmp['class']= "struct"
                  tmp['type'] = string.format("%s",class_type)
                end

--                tmp['mandatory'] = (v2:attr('mandatory')) and v2:attr('mandatory') or 'true'
                tmp['mandatory'] = v2:attr('mandatory') or 'true'
                if (v2:attr('array')) then tmp['array'] = v2:attr('array') end
                if (v2:attr('minsize') and v2:attr('maxsize')) then
                    tmp['minsize'] = v2:attr('minsize')
                    tmp['maxsize'] = v2:attr('maxsize')
                end
                if (v2:attr('minlength')) then tmp['minlength'] = tonumber(v2:attr('minlength')) end
                if (v2:attr('maxlength')) then tmp['maxlength'] = tonumber(v2:attr('maxlength')) end
                if (v2:attr('minvalue')) then tmp['minvalue'] = tonumber(v2:attr('minvalue')) end
                if (v2:attr('maxvalue')) then tmp['maxvalue'] = tonumber(v2:attr('maxvalue')) end
                
                retval[v2:attr('name')] = tmp
              end
            end
          end
        end
      end
  
  return retval
  end
   
  local function errorMsgToString(tbl)
    local tmp = ''
    if type(tbl) == 'table' then
      for _,v in pairs(tbl) do
        if type(v) == 'table' then
          tmp = tmp ..errorMsgToString(v) ..'\n'
        else
          tmp = tmp ..v ..'\n'
        end       
      end
      return tmp
    end  
    
   return tostring(tbl)    
  end
  
  local function compare_type(elem1, elem2)
    if     (elem1 == 'number'  and elem2 == 'Integer') then return true
    elseif (elem1 == 'number'  and elem2 == 'Float')   then return true
    elseif (elem1 == 'string'  and elem2 == 'String')  then return true
    elseif (elem1 == 'boolean' and elem2 == 'Boolean') then return true
    else return false
    end
  end

  local function nodeVerify(xmlNode,dataNode, key)
    if (xmlNode.class == 'enum') then
      if (not types.enum[xmlNode['type'] ][dataNode]) then
		    print(dump(dataNode))
                    bool_result = false 
                    errorMessage[ key ] = "expected: '" .. key .."' with type  [ Enum ]"
      end
    elseif (xmlNode.class == 'struct') then
      if (not types.struct[xmlNode['type'] ][dataNode]) then
                    bool_result = false 
                    errorMessage[ key ] = "expected: '" .. key .."' with type  [ Struct ]"
      end
    elseif xmlNode.array == 'true' then
	    if (type(dataNode) == 'table' ) then
		    for _,arrElement in ipairs(dataNode) do
		      while true do
            if (xmlNode.class == 'Enum' and types.enum[xmlNode['type'] ][dataNode] ) then break
            elseif (xmlNode.class == 'Struct' and types.struct[xmlNode['type'] ][dataNode] ) then break
            elseif(compare_type(string.lower(type(arrElement)), xmlNode.class)) then break
            else
	    		    bool_result = false
    			    errorMessage[ key ] = "not valid type: into "..key .. " " .. string.lower(type(arrElement)) .. " " .. xmlNode.class
              break
            end
		      end
		    end
      else
        bool_result = false
        errorMessage[ key ] = "expected: '" .. key .."' with type  [ array ]"
	    end
    else
	    if (types.classes[xmlNode.class] ~= 'nil') then 
		    if (not  compare_type(string.lower(type(dataNode)), xmlNode.class) ) then
    			bool_result = false
    			errorMessage[ key ] = "not valid type '"..key .."': current type - '".. string.lower(type(dataNode)) .."' ; Avalible - '".. xmlNode.class .."'"
		    end
	    else
          errorMessage[ key ] = "not valid type: "..key
	    end
    end
  end

  local function schemaCompare(xml_table,user_data)
    if (type(xml_table)~="table") then 
      return nil, "Empty Data" 
    end
    
    if (not mandatory_check) then
      for k2,v2 in pairs(user_data) do
        if(xml_table[k2]) then
          nodeVerify(xml_table[k2], user_data[k2], k2)
        else
          bool_result = false
          errorMessage[ k2 ] = "not valid property: ".. k2
        end
      end
    else
      for k1,v1 in pairs(xml_table) do
        if(user_data[k1]) then
          nodeVerify(xml_table[k1], user_data[k1], k1)
        else
          if(xml_table[k1].mandatory == 'true') then
            bool_result = false
            errorMessage[ k1 ] = "not present : ".. k1
        end
      end
    end
  end

  return bool_result, errorMsgToString(errorMessage)
end

function module.json_validate(table1, table2)
   local avoid_loops = {}
   local function recurse(t1, t2)
      if (type(t1) ~= type(t2)) then return false end
      if (type(t1) ~= "table") then return t1 == t2 end
      if (avoid_loops[t1]) then return avoid_loops[t1] == t2 end
      
      avoid_loops[t1] = t2
      local t2keys = {}
      local t2tablekeys = {}
      
      for k, _ in pairs(t2) do
         if type(k) == "table" then table.insert(t2tablekeys, k) end
         t2keys[k] = true
      end
    
      for k1, v1 in pairs(t1) do
         local v2 = t2[k1]
         if (type(k1) == "table") then
            local ok = false
            for i, tk in ipairs(t2tablekeys) do
               if table_eq(k1, tk) then
                  table.remove(t2tablekeys, i)
                  t2keys[tk] = nil
                  ok = true
                  break
               end
            end
            if not ok then return false,"Missing one or more fields" end
         else
           if (t2keys[k1]) then
              if v2 == nil then return false, string.format("Missing value for: '%s'",k1) end
              t2keys[k1] = nil
           else
              t2keys[k1] = v1
              return false, string.format("Missing: '%s'",k1)
           end  
         end
      end
  
      if (next(t2keys)) then return false,"Missing one or more fields" end
      return true
   end
   return recurse(table1, table2)
end
   
   if (schema == module.HMI) then
      doc = mobile_api
      if not doc then return nil,"Cannot open data/MOBILE_API.xml" end
      types = hmi_types
  elseif (schema == module.MOBILE) then
      doc = hmi_api 
      if not doc then return nil,"Cannot open data/HMI_API.xml" end
      types = mob_types        
  else 
      return nil,"Unknown schema type"
  end

  local xml_schema = get_xml_shema_validation(doc,types,function_id,msgType)  

  return schemaCompare(xml_schema,user_data)
  
end 

function module.validate_hmi_request(function_id,user_data, mandatory_check)
  return compare(module.HMI,function_id, 'request',user_data, mandatory_check)
end

function module.validate_mobile_request(function_id,user_data, mandatory_check)
  return compare(module.MOBILE,function_id, 'request',user_data, mandatory_check)
end

function module.validate_hmi_response(function_id,user_data, mandatory_check)
  return compare(module.HMI,function_id, 'response',user_data, mandatory_check)
end

function module.validate_mobile_response(function_id,user_data, mandatory_check)
  return compare(module.MOBILE,function_id, 'response',user_data, mandatory_check)
end  

function module.validate_mobile_notification(function_id,user_data, mandatory_check)
  return compare(module.MOBILE,function_id, 'notification',user_data, mandatory_check)
end  

function module.validate_hmi_notification(function_id,user_data, mandatory_check)
  return compare(module.HMI,function_id, 'notification',user_data, mandatory_check)
end  


return module