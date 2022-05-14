local packageName = "Player Extensions"
local logger = GPM.Logger( packageName )
local PLAYER = FindMetaTable( "Player" )

/*
    Functions:
        `string` PLAYER:Country() - returns ISO 3166-1 alpha-2 countryc code

        Server:
            PLAYER:SetCountry( `string` country_code ) - sets country code
*/
do

    local default_language = "gb"
    local network_name = "Player@Country"

    -- Language Extensions Support
    local cvar = GetConVar( "default_language" )
    if (cvar) then
        default_language = cvar:GetString()
        cvars.AddChangeCallback("default_language", function( name, old, new )
            default_language = new
        end, packageName)
    end

    if (CLIENT) then
        net.Receive(network_name, function()
            net.Start( network_name )
                net.WriteString( system.GetCountry():lower() )
            net.SendToServer()
        end)
    end

    function PLAYER:Country()
        return self:GetNWString( network_name, default_language )
    end

    if (SERVER) then

        function PLAYER:SetCountry( country_code )
            return self:SetNWString( network_name, country_code or default_language )
        end

        util.AddNetworkString( network_name )
        hook.Add("PlayerInitialized", network_name, function( ply )
            net.Start( network_name )
            net.Send( ply )
        end)

        net.Receive(network_name, function( len, ply )
            if IsValid( ply ) and (ply:GetNWString( network_name, false ) == false) then
                ply:SetCountry( net.ReadString() )
            end
        end)

    end

end

/*
    Functions:
        `boolean` PLAYER:IsListenServerHost() - Returns `true` if player is server host
*/
do

    if (CLIENT) then

        if game.SinglePlayer() then
            function PLAYER:IsListenServerHost()
                return true
            end
        else
            if game.IsDedicated() then
                function PLAYER:IsListenServerHost()
                    return false
                end
            else
                function PLAYER:IsListenServerHost()
                    return self:GetNWBool( "__islistenserverhost", false )
                end
            end
        end

    end

    if (SERVER) and not game.SinglePlayer() and not game.IsDedicated() then
        hook.Add("PlayerInitialSpawn", "PLAYER:IsListenServerHost()", function( ply )
            if ply:IsListenServerHost() then
                ply:SetNWBool( "__islistenserverhost", true )
                hook.Remove( "PlayerInitialSpawn", "PLAYER:IsListenServerHost()" )
            end
        end)
    end

end

/*
    Functions:
        `string` PLAYER:SourceNick() - Returns original player nickname
        `string` PLAYER:Nick() - Returns player nickname
        `string` PLAYER:Name() - Returns player nickname
        `string` PLAYER:GetName() - On client that player nickname, on server that player mapping entity name

        Server:
            PLAYER:SetNick( `string` nickname ) - Sets globaly player nickname
*/
do

    local network_name = "Player@CustomNickname"

    PLAYER.SourceNick = environment.saveFunc( "PLAYER.Nick", PLAYER.Nick )

    function PLAYER:Nick()
        return self:GetNWString( network_name, self:SourceNick() )
    end

    PLAYER.Name = PLAYER.Nick

    PLAYER.GetName = (CLIENT) and PLAYER.Nick or FindMetaTable( "Entity" ).GetName

    if (SERVER) then

        local nicknames = {}
        function PLAYER:SetNick( nickname )
            logger:info( "Player ({1}), nickname changed: '{2}' -> '{3}'", self:EntIndex(), self:Nick(), nickname )
            self:SetNWString( network_name, (nickname == nil) and self:SourceNick() or nickname )

            if self:IsBot() then return end
            nicknames[ self:SteamID64() ] = nickname
        end

        hook.Add("PlayerInitialSpawn", network_name, function( ply )
            local nickname = nicknames[ ply:SteamID64() ]
            if (nickname ~= nil) then
                ply:SetNick( nickname )
            end
        end)

    end

end

/*
    Functions:
        PLAYER:ConCommand( `string` cmd ) - Runs concommand on client
*/
do

    local network_name = "Player@ConCommand"

    if (SERVER) then

        local net_WriteString = net.WriteString
        local net_Start = net.Start
        local net_Send = net.Send

        function PLAYER:ConCommand( cmd )
            logger:debug( "ConCommand '{1}' runned on '{2}'", cmd, ply )
            net_Start( network_name )
                net_WriteString( cmd )
            net_Send( self )
        end

    end

    if (CLIENT) then

        local net_ReadString = net.ReadString
        local net_Receive = net.Receive

        hook.Add("PlayerInitialized", network_name, function( ply )
            net_Receive(network_name, function()
                ply:ConCommand( net_ReadString() )
            end)
        end)

    end

end

/*
    Hooks:
        GM:OnPlayerDropWeapon( `entity` ply, `entity` wep, `vector` target, `vector` velocity ) - Return false for block weapon drop
*/
if (SERVER) then

    local drop_weapon = environment.saveFunc( "PLAYER.DropWeapon", PLAYER.DropWeapon )

    PLAYER.SourceDropWeapon = drop_weapon

    function PLAYER:DropWeapon( ... )
        if (hook.Run( "OnPlayerDropWeapon", self, ... ) == false) then
            return
        end

        return drop_weapon( self, ... )
    end

end

/*
    Functions:
        `string` PLAYER:GetSQL( `string` key, `any` default )
        `boolean` PLAYER:SetSQL( `string` key, `string` value )
        `boolean` PLAYER:ClearSQL( `string` key )
*/
do

    module( "player_db", package.seeall )

    local sql_Query = sql.Query
    local sql_SQLStr = sql.SQLStr

    function CreateTable( str )
        game_ready.wait(function()
            sql_Query( "CREATE TABLE IF NOT EXISTS `" .. str .."` ( `steamid64` TEXT NOT NULL PRIMARY KEY, `data` TEXT NOT NULL);" )
        end)
    end

    local table_name = CreateConVar( "mysql_player_db_table", "player_db", FCVAR_ARCHIVE, " - MySQL table name with players data." ):GetString()
    CreateTable( table_name )

    cvars.AddChangeCallback("mysql_player_db_table", function( name, old, new )
        CreateTable( new )
        table_name = new
    end, packageName)

    do

        local util_JSONToTable = util.JSONToTable
        local sql_QueryValue = sql.QueryValue

        function GetData( steamid64 )
            local result = sql_QueryValue( "SELECT `data` FROM `" .. table_name .. "` WHERE `steamid64` = " .. sql_SQLStr( steamid64 ) )
            if !result then
                return {}
            end

            return util_JSONToTable( result ) or {}
        end

    end

    do

        local cache = {}
        local SysTime = SysTime

        function PLAYER:GetSQL( key, default )
            local steamid64 = self:SteamID64()
            if (cache[ steamid64 ] == nil) then
                cache[ steamid64 ] = {}
            end

            local entry = cache[ steamid64 ][ key ]
            if (entry == nil) or (SysTime() > entry[ 1 ]) then
                cache[ steamid64 ][ key ] = { SysTime() + 30, GetData( steamid64 )[ key ] }
            end

            return cache[ steamid64 ][ key ][ 2 ] or default
        end

    end

    do

        local util_TableToJSON = util.TableToJSON
        local table_Merge = table.Merge
        local sql_Commit = sql.Commit
        local sql_Begin = sql.Begin
        local pairs = pairs

        local queue = {}

        function SyncData()
            sql_Begin()

            for steamid64, data in pairs( queue ) do
                if (data == nil) then continue end
                sql_Query( "INSERT OR REPLACE INTO `" .. table_name .."` ( steamid64, data ) VALUES ( " .. sql_SQLStr( steamid64 ) .. ", " .. sql_SQLStr( util_TableToJSON( table_Merge( GetData( steamid64 ), data ) ) ) .. " );" )
            end

            sql_Commit()
        end

        do
            local timer_Create = timer.Create
            function AddQueue( steamid64, key, value, force )
                if (queue[ steamid64 ] == nil) then
                    queue[ steamid64 ] = {}
                end

                queue[ steamid64 ][ key ] = value

                if (force) then
                    SyncData()
                end

                timer_Create( "player_db", 0.025, 1, SyncData )

                return true
            end
        end

    end

    function PLAYER:SetSQL( key, value, force )
        if self:IsBot() then return false end
        return AddQueue( self:SteamID64(), key, value, force )
    end

    function PLAYER:ClearSQL()
        if self:IsBot() then return false end
        return sql_Query( "DELETE FROM `" .. table_name .."` WHERE `steamid64` = " .. self:SteamID64() .. ";" ) ~= false
    end

end

/*
    Functions:
        Server:
            `boolean` PLAYER:LoadData() - Load player data
            `boolean` PLAYER:SaveData() - Save player data
            `table` PLAYER:GetAllData() - Get all player data
            PLAYER:SetData( key, value ) - Set player data var
            `any` PLAYER:GetData( key, default ) - Get player data var

        Hooks:
            GM:PlayerDataLoaded( ply, result, data )
            GM:PlayerDataSaved( ply, result )
*/
if (SERVER) then

    local sql_name = "Player@Data"
    local hook_Run = hook.Run

    do

        local util_JSONToTable = util.JSONToTable
        local empty_string = ""

        function PLAYER:LoadData()
            local sql_data = self:GetSQL( sql_name, nil )
            if (sql_data ~= nil) then
                local data = util_JSONToTable( sql_data )
                if (data ~= nil) then
                    self.PlayerData = data
                    hook_Run( "PlayerDataLoaded", self, true, data )
                    return true
                end
            end

            self.PlayerData = {}
            hook_Run( "PlayerDataLoaded", self, false, self.PlayerData )
            return false
        end

    end

    do

        local util_TableToJSON = util.TableToJSON
        local empty_table = {}

        function PLAYER:SaveData( force )
            local result = self:SetSQL( sql_name, util_TableToJSON( self.PlayerData or empty_table ), force )
            hook_Run( "PlayerDataSaved", self, result )
            return result
        end

    end

    hook.Add( "PlayerInitialSpawn", sql_name, PLAYER.LoadData )
    hook.Add( "PlayerDisconnected", sql_name, PLAYER.SaveData )

    hook.Add("ShutDown", sql_name, function()
        hook.Remove( "PlayerDisconnected", sql_name )
        for num, ply in ipairs( player.GetAll() ) do
            ply:SaveData( true )
        end
    end)

    hook.Add("PlayerDataLoaded", sql_name, function( ply, result )
        logger:info( "Player {1} ({2}) data {3}.", ply:Nick(), ply:SteamID(), result and "successfully loaded" or "load failed" )
    end)

    hook.Add("PlayerDataSaved", sql_name, function( ply, result )
        logger:info( "Player {1} ({2}) data {3}.", ply:Nick(), ply:SteamID(), result and "successfully saved" or "save failed" )
    end)

    function PLAYER:SetData( key, value )
        self.PlayerData[ key ] = value
    end

    function PLAYER:GetData( key, default )
        return self.PlayerData[ key ] or default
    end

    function PLAYER:GetAllData()
        return self.PlayerData
    end

end