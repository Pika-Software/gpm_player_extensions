# gpm_player_country
 Where are you?

### Functions:
```lua
    `string` PLAYER:Country() -- returns ISO 3166-1 alpha-2 countryc code
    `boolean` PLAYER:IsListenServerHost() -- Returns `true` if player is server host
    `string` PLAYER:SourceNick() -- Returns original player nickname
    `string` PLAYER:Nick() -- Returns player nickname
    `string` PLAYER:Name() -- Returns player nickname
    `string` PLAYER:GetName() -- On client that player nickname, on server that player mapping entity name

    PLAYER:ConCommand( `string` cmd ) -- Runs concommand on client

    Server:
        PLAYER:SetCountry( `string` country_code ) -- sets country code
        PLAYER:SetNick( `string` nickname ) -- Sets globaly player nickname
        `boolean` PLAYER:LoadData() -- Load player data
        `boolean` PLAYER:SaveData( `boolean` force ) -- Save player data
        PLAYER:SetData( `string` key, `any` value, `boolean` force ) -- Set player data var
        `any` PLAYER:GetData( `string` key, `any` default ) -- Get player data var
        `table` PLAYER:GetAllData() -- Get all player data
```

### Hooks:
```lua
    GM:OnPlayerDropWeapon( `entity` ply, `entity` wep, `vector` target, `vector` velocity ) -- Return false for block weapon drop
    GM:PlayerDataLoaded( `entity` ply, `boolean` result, `table` data ) -- Calls on player data is loaded and ready to use
    GM:PlayerDataSaved( `entity` ply, `boolean` result ) -- Calls after player data saved
```
