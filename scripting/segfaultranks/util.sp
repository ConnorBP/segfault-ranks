#include <cstrike>
#include <sdktools>

static char _colorNames[][] =  { "{NORMAL}", "{DARK_RED}", "{PINK}", "{GREEN}", 
	"{YELLOW}", "{LIGHT_GREEN}", "{LIGHT_RED}", "{GRAY}", 
	"{ORANGE}", "{LIGHT_BLUE}", "{DARK_BLUE}", "{PURPLE}" };
static char _colorCodes[][] =  { "\x01", "\x02", "\x03", "\x04", "\x05", "\x06", 
	"\x07", "\x08", "\x09", "\x0B", "\x0C", "\x0E" };


// ranks cache
Handle g_steamRankCache;

/** Chat aliases loaded **/
ArrayList g_ChatAliases;
ArrayList g_ChatAliasesCommands;
ArrayList g_ChatAliasesModes;


stock void Colorize(char[] msg, int size, bool stripColor = false) {
	for (int i = 0; i < sizeof(_colorNames); i++) {
		if (stripColor)
			ReplaceString(msg, size, _colorNames[i], "\x01"); // replace with white
		else
			ReplaceString(msg, size, _colorNames[i], _colorCodes[i]);
	}
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


int GetCurrentPlayers() 
{
	int count;
	for (int i = 1; i <= MaxClients; i++) {
		if (IsPlayer(i)) {
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