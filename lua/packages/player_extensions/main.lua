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

    local database_name = "players_db"

    local sql_SQLStr = sql.SQLStr
    local sql_Query = sql.Query
    local sql_QueryValue = sql.QueryValue

    local sample = "%s[%s]"
    function PLAYER:GetSQL( key, default )
        return sql_QueryValue( "SELECT value FROM " .. database_name .. " WHERE infoid = " .. sql_SQLStr( sample:format( self:SteamID64(), key ) ) .. " LIMIT 1" ) or default
    end

    function PLAYER:SetSQL( key, value )
        return sql_Query( "REPLACE INTO " .. database_name .. " (infoid, value) VALUES (" .. sql_SQLStr( sample:format( self:SteamID64(), key ) ) .. ", " .. sql_SQLStr(value) .. " )" ) ~= false
    end

    function PLAYER:ClearSQL( key )
        return sql_Query( "DELETE FROM " .. database_name .. " WHERE infoid = " .. sql_SQLStr( sample:format( self:SteamID64(), key ) ) ) ~= false
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
*/
if (SERVER) then

    local sql_name = "Player@Data"

    do

        local util_JSONToTable = util.JSONToTable
        local util_Decompress = util.Decompress
        local empty_string = ""

        function PLAYER:LoadData()
            local sql_data = self:GetSQL( sql_name, nil )
            if (sql_data ~= nil) then
                local data = util_Decompress( sql_data )
                if (data ~= empty_string) then
                    local json = util_JSONToTable( data )
                    if (json ~= nil) then
                        self.PlayerData = json
                        return true
                    end
                end
            end

            self.PlayerData = {}
            return false
        end

    end

    do

        local util_TableToJSON = util.TableToJSON
        local util_Compress = util.Compress
        local empty_table = {}

        function PLAYER:SaveData()
            return sefl:SetSQL( sql_name, util_Compress( util_TableToJSON( self.PlayerData or empty_table ) ) )
        end
    end

    hook.Add("PlayerInitialSpawn", sql_name, function( ply )
        ply:LoadData()
    end)

    hook.Add("PlayerDisconnected", sql_name, function( ply )
        ply:SaveData()
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