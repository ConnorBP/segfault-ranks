#include <cstrike>
#include <sdktools>

static char _colorNames[][] =  { "{NORMAL}", "{DARK_RED}", "{PINK}", "{GREEN}", 
    "{YELLOW}", "{LIGHT_GREEN}", "{LIGHT_RED}", "{GRAY}", 
    "{ORANGE}", "{LIGHT_BLUE}", "{DARK_BLUE}", "{PURPLE}" };
static char _colorCodes[][] =  { "\x01", "\x02", "\x03", "\x04", "\x05", "\x06", 
    "\x07", "\x08", "\x09", "\x0B", "\x0C", "\x0E" };

stock void Colorize(char[] msg, int size, bool stripColor = false) {
    for (int i = 0; i < sizeof(_colorNames); i++) {
        if (stripColor)
            ReplaceString(msg, size, _colorNames[i], "\x01"); // replace with white
        else
            ReplaceString(msg, size, _colorNames[i], _colorCodes[i]);
    }
}

// Takes only whitelisted characters from a string into a new string
stock void CleanStringCharacters(char[] oldString, char[] newString, int newStringSize) {
    char allowableChars[39] = "abcdefghijknmnopqrstuvwxyz0123456789-_~"; 
    new o=0;
    new n=0;
    // assumes old string is zero terminated. Leaves 1 char in new string to zero terminate it as well
    while (oldString[o] != '\0' && n < newStringSize-1) {
        // if the current character is in the allowable chars string then add it to our new string
        if(StrContains(allowableChars, oldString[o], false)) {
            // the character was in the allowable characters list, add it to our new string
            newString[n] = oldString[o];
            // move to next char in newstring
            n++;
        }
        // always move to next char in oldstring
        o++;
    } 
    // then pad the rest with zero
    while(n<newStringSize) {
        newString[n] = '\0';
        n++;
    }
}

stock void GetPlaceStr(int place, char[] buffer, int bufferSize) {

    /*n =>
    n+(
        n/10%10==1
        ||(n%=10)<1
        ||n>3
        ?"th":n<2?"st":n<3?"nd":"rd"
    );*/

    int k = place % 10;
    char placePostFix[4] = "";
    if(place/10%10==1 || k<1 || k > 3) {
        placePostFix = "th";
    } else if(k<2) {
        placePostFix = "st";
    } else if (k<3) {
        placePostFix = "nd";
    } else {
        placePostFix = "rd";
    }
        
    Format(buffer, bufferSize, "%i%s", place, placePostFix);
}

/** Chat aliases loaded **/
ArrayList g_ChatAliases;
ArrayList g_ChatAliasesCommands;
ArrayList g_ChatAliasesModes;

// Replaces the clients scoreboard points with their rws * 10 to allow one decimal place
stock void SetClientRwsDisplay(int client, float rws) {
    CS_SetClientContributionScore(client, RoundFloat(rws * 10.0));
}

/**
 * Returns if a client is valid.
 */
stock bool IsValidClient(int client) {
    return client > 0 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client);
}

stock bool IsPlayer(int client) {
    return IsValidClient(client) && !IsFakeClient(client);
}

stock bool IsPossibleLeader(int client) {
    return client > 0 && client <= MaxClients && IsClientConnected(client) && !IsFakeClient(client);
}

// returns number of players on the server (includes spectators)
stock int GetTotalPlayers() 
{
    int count;
    for (int i = 1; i <= MaxClients; i++) {
        if (IsPlayer(i)) {
            count++;
        }
    }
    return count;
}

// returns number of players on the server in an active team
stock int GetActivePlayers() 
{
    int count;
    for (int i = 1; i <= MaxClients; i++) {
        if (OnActiveTeam(i)) {
            count++;
        }
    }
    return count;
}

/**
 * Returns the number of human clients on a team.
 */
stock int GetNumHumansOnTeam(int team) {
    int count = 0;
    for (int i = 1; i <= MaxClients; i++) {
        if (IsValidClient(i) && !IsFakeClient(i))
            count++;
    }
    return count;
}

/**
 * Returns the number of clients that are actual players in the game.
 */
stock int GetRealClientCount() {
    int clients = 0;
    for (int i = 1; i <= MaxClients; i++) {
        if (IsPlayer(i)) {
            clients++;
        }
    }
    return clients;
}

stock int CountAlivePlayersOnTeam(int team) {
    int count = 0;
    for (int i = 1; i <= MaxClients; i++) {
        if (IsPlayer(i) && IsPlayerAlive(i) && GetClientTeam(i) == team)
            count++;
    }
    return count;
}

stock bool OnActiveTeam(int client) {
    if (!IsPlayer(client))
        return false;
    
    int team = GetClientTeam(client);
    return team == CS_TEAM_CT || team == CS_TEAM_T;
}

public bool IsOnDb(int client) { 
    return userData[client].on_db;
    //return true;//TEMPORARY FOR DEBUG TODO:REMOVE
}

// Re-Usable checks for wether or not we should rank players right now
stock bool ShouldRank() {
    // ranks should be calculated if it is not warmup, and there are at least
    // the min player count (2 by default) on teams
    // TODO: add check for if ranking is by round or by match either here or
    // somewhere else
    return !CheckIfWarmup() && minimumPlayers <= GetActivePlayers();
}

// returns true if it is currently the warmup period
stock bool CheckIfWarmup() { return GameRules_GetProp("m_bWarmupPeriod") == 1; }



// cookies

/*stock int GetCookieInt(int client, Handle cookie, int defaultValue = 0) {
    char buffer[MAX_INTEGER_STRING_LENGTH];
    GetClientCookie(client, cookie, buffer, sizeof(buffer));
    
    if (StrEqual(buffer, ""))
        return defaultValue;
    
    return StringToInt(buffer);
}

stock float GetCookieFloat(int client, Handle cookie, float defaultValue = 0.0) {
    char buffer[MAX_FLOAT_STRING_LENGTH];
    GetClientCookie(client, cookie, buffer, sizeof(buffer));
    
    if (StrEqual(buffer, ""))
        return defaultValue;
    
    return StringToFloat(buffer);
}

stock void SetCookieInt(int client, Handle cookie, int value) {
    char buffer[MAX_INTEGER_STRING_LENGTH];
    IntToString(value, buffer, sizeof(buffer));
    SetClientCookie(client, cookie, buffer);
}

stock void SetCookieFloat(int client, Handle cookie, float value) {
    char buffer[MAX_FLOAT_STRING_LENGTH];
    FloatToString(value, buffer, sizeof(buffer));
    SetClientCookie(client, cookie, buffer);
}*/