" Test file to verify Lua modules are loading correctly

function! TestLuaModule()
    echo "Testing Lua module loading..."
    
    try
        let output = luaeval('require("augment") ~= nil')
        echo "Module loaded: " . output
        
        let has_start_client = luaeval('type(require("augment").start_client) == "function"')
        echo "Has start_client function: " . has_start_client
        
        let has_open_buffer = luaeval('type(require("augment").open_buffer) == "function"')
        echo "Has open_buffer function: " . has_open_buffer
        
        let has_notify = luaeval('type(require("augment").notify) == "function"')
        echo "Has notify function: " . has_notify
        
        let has_request = luaeval('type(require("augment").request) == "function"')
        echo "Has request function: " . has_request
        
        echo "TEST SUCCESSFUL"
    catch
        echo "Error: " . v:exception
    endtry
endfunction

" Call the test function
call TestLuaModule()