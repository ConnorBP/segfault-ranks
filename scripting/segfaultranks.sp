#define PLUGIN_VERSION "0.0.1-dev"
#define MESSAGE_PREFIX "[\x05Ranks\x01] "
#define DEBUG_CVAR "sm_segfaultranks_debug"

#include <clientprefs>
#include <cstrike>
#include <sourcemod>
#include <sdktools>

#include <logdebug>
#include <priorityqueue>
#include "segfaultranks/util.sp"
#include "include/segfaultranks.inc"



/*
 * This isn't meant to be a comprehensive stats system, it's meant to be a simple
 * way to balance teams to replace manual stuff using a (exponentially) weighted moving average.
 * The update takes place every round, following this equation
 *
 * R' = (1-a) * R_prev + alpha * R
 * Where
 *    R' is the new rating
 *    a is the alpha factor (how much a new round counts into the new rating)
 *    R is the round-rating
 *
 * Alpha is made to be variable, where it decreases linearly to allow
 * ratings to change more quickly early on when a player has few rounds played.
 */
#define ALPHA_INIT 0.1
#define ALPHA_FINAL 0.003
#define ROUNDS_FINAL 250.0
#define AUTH_METHOD AuthId_Steam2


//forwards

Handle g_fwdOnPlayerLoaded = INVALID_HANDLE;
Handle g_fwdOnPlayerSaved = INVALID_HANDLE;

Handle g_hOnHelpCommand = INVALID_HANDLE;


bool DEBUGGING = true; //TODO: MIX THIS IN WITH THE DEBUGGING CVAR
bool g_bEnabled = true; //TODO add a convar to disable this plugin, and verify that the database is handles properly when the plugin is disabled while already running

// Database variables



// id, steam, name, lastip, connected, lastconnected, elo, rws, rounds_total, rounds_won, kills, deaths, assists, suicides, teamkills, headshots, total_damage, mvp, matches_won, matches_lost, matches_tied

static const char g_sMysqlCreate[] = "CREATE TABLE IF NOT EXISTS `%s` (id INTEGER PRIMARY KEY, steam TEXT, name TEXT, lastip TEXT, connected NUMERIC, lastconnected NUMERIC, elo FLOAT, rws FLOAT, rounds_total NUMERIC, rounds_won NUMERIC, kills NUMERIC, deaths NUMERIC, assists NUMERIC, suicides NUMERIC, teamkills NUMERIC, headshots NUMERIC, total_damage NUMERIC, mvp NUMERIC, matches_won NUMERIC, matches_lost NUMERIC, matches_tied NUMERIC) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci";
static const char g_sSqlInitInsert[] = "INSERT INTO `%s` VALUES (NULL,'%s','%s','%s','0','0','500.0','0.0','0','0','0','0','0','0','0','0','0','0','0','0','0');";
static const char g_sSqlSave[] = "UPDATE `%s` SET name='%s',lastip='%s',elo='%f',rws='%f',rounds_total='%i',rounds_won='%i',kills='%i',deaths='%i',assists='%i',suicides='%i',teamkills='%i',headshots='%i',total_damage='%i',mvp ='%i',matches_won='%i',matches_lost='%i',matches_tied='%s' WHERE steam = '%s';";
static const char g_sSqlRetrieveClient[] = "SELECT * FROM `%s` WHERE steam='%s';";

Handle g_hStatsDb;
char g_sSQLTable[200];
bool g_bMysql = true;

// wether or not a user is on/loaded from the db yet
bool OnDB[MAXPLAYERS + 1];

// Preventing duplicates
char g_aClientSteam[MAXPLAYERS + 1][64];
char g_aClientName[MAXPLAYERS + 1][MAX_NAME_LENGTH];
char g_aClientIp[MAXPLAYERS + 1][64];

// Local cache of state user stats
STATS_NAMES g_aStats[MAXPLAYERS + 1];
// instead of g_aSession stats for all stats we have the time user connected this session (used for calculated time since last connected)
int g_aSessionConnectedTime[MAXPLAYERS +1];

// convar local variables

//minimum players required for ranks to calculate
int g_MinimumPlayers;
int g_RankMode;
//int g_DaysToNotShowOnRank;
int g_MinimalRounds;
bool g_bRankCache;

//int g_TotalPlayers;//this is set by sql_getplayerscallback for some reason

//Convars

ConVar g_MessagePrefixCvar;

ConVar g_cvarMysql;
ConVar g_cvarSQLTable;
ConVar g_AllowStatsOtherCommandCvar;
//ConVar g_RecordStatsCvar;
ConVar g_cvarAutopurge;
ConVar g_cvarMinimumPlayers;
ConVar g_cvarRankMode;
//ConVar g_cvarDaysToNotShowOnRank;
ConVar g_cvarMinimalRounds;
ConVar g_cvarRankCache;
//ConVar g_RankEachRoundCvar;
//ConVar g_SetEloRanksCvar;
//ConVar g_ShowRWSOnScoreboardCvar
//ConVar g_ShowRankOnScoreboardCvar;


//cookies
//Handle g_RWSCookie = INVALID_HANDLE;//TODO:REMOVE, USE DB FOR FINAL STORAGE AND NOT COOKIES
//Handle g_EloRankCookie = INVALID_HANDLE;//TODO:REMOVE, USE DB FOR FINAL STORAGE AND NOT COOKIES
//Handle g_RoundsPlayedCookie = INVALID_HANDLE;//TODO:REMOVE, USE DB FOR FINAL STORAGE AND NOT COOKIES

/** Client stats **/
//float g_PlayerRWS[MAXPLAYERS + 1];
//int g_PlayerRounds[MAXPLAYERS + 1];
//bool g_PlayerHasStats[MAXPLAYERS + 1];

/** Rounds stats **/
//int g_RoundPoints[MAXPLAYERS + 1];



#include "segfaultranks/natives.sp"

public Plugin myinfo = {
    name = "CS:GO RWS Ranking System",
    author = "segfault",
    description = "Keeps track of user rankings based on an RWS Elo system",
    version = PLUGIN_VERSION,
    url = "https://segfault.club"
};


public void OnPluginStart() {
    InitDebugLog(DEBUG_CVAR, "segfaultranks");
    //LoadTranslations("segfaultranks.phrases");
    LoadTranslations("common.phrases");

    // Initiate the rankings cache Global Adt Array
    g_steamRankCache = CreateArray(ByteCountToCells(128));

    HookEvent("bomb_defused", Event_Bomb);
    HookEvent("bomb_planted", Event_Bomb);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("player_hurt", Event_DamageDealt);
    HookEvent("round_end", Event_RoundEnd);

    RegAdminCmd("sm_dumprws", Command_DumpRWS, ADMFLAG_KICK,
              "Dumps all player historical rws and rounds played");
    RegConsoleCmd("sm_rws", Command_RWS, "Show player's historical rws");
    RegConsoleCmd("sm_rank", Command_Rank, "Show player's ELO Rank");
    RegConsoleCmd("sm_top", Command_Leaderboard, "Show player's leaderboard position");
    //SegfaultRanks_AddChatAlias(".rws", "sm_rws");
    //SegfaultRanks_AddChatAlias(".stats", "sm_rws");
    //SegfaultRanks_AddChatAlias(".rank", "sm_rank");
    //SegfaultRanks_AddChatAlias(".top", "sm_top");

    g_MessagePrefixCvar = CreateConVar("sm_segfaultranks_message_prefix", "[{PURPLE}Ranks{NORMAL}]", "The tag applied before plugin messages. If you want no tag, you can set an empty string here.");
    g_AllowStatsOtherCommandCvar = CreateConVar("sm_segfaultranks_allow_stats_other", "1", "Whether players can use the .rws or !rws command on other players");
    //g_RecordStatsCvar = CreateConVar("sm_segfaultranks_record_stats", "1", "Whether rws should be recorded while not in warmup (set to 0 to disable changing players rws stats)");
    g_cvarAutopurge = CreateConVar("sm_segfaultranks_autopurge", "0", "Auto-Purge inactive players? X = Days  0 = Off", _, true, 0.0);
    g_cvarMinimumPlayers = CreateConVar("sm_segfaultranks_minimumplayers", "2", "Minimum players to start giving points", _, true, 0.0);
    g_cvarRankMode = CreateConVar("sm_segfaultrank_rank_mode", "1", "Rank by what? 1 = by rws 2 = by kdr 3 = by elo", _, true, 1.0, true, 3.0);
    //g_cvarDaysToNotShowOnRank = CreateConVar("sm_segfaultrank_timeout_days", "0", "Days inactive to not be shown on rank? X = days 0 = off", _, true, 0.0);
    g_cvarMinimalRounds = CreateConVar("sm_segfaultrank_minimal_rounds", "0", "Minimal rounds played for rank to be displayed", _, true, 0.0);
    //g_RankEachRoundCvar = CreateConVar("sm_segfaultranks_rank_rounds", "1", "Sets if Elo ranks should be updated every round instead of at match end. (Useful for retake ranking)");
    //g_SetEloRanksCvar = CreateConVar("sm_segfaultranks_display_elo_ranks", "2", "Wether or not to display user ranks based on calculated total ELO. (S,G,A,B,etc) 0=Don't Display 1=Calculate elo ranks 2=Use top RWS", _, true, 0.0, true, 2.0);
    //g_ShowRWSOnScoreboardCvar = CreateConVar("sm_segfaultranks_display_rws", "1", "Whether rws stats for current map are to be displayed on the ingame scoreboard in place of points.");
    //g_ShowRankOnScoreboardCvar = CreateConVar("sm_segfaultranks_display_rank", "1", "Whether rws stats for current map are to be displayed on the ingame scoreboard in place of points.");
    g_cvarRankCache = CreateConVar("sm_segfaultranks_rank_cache", "0", "Get player rank via cache, auto build cache on every OnMapStart.", _, true, 0.0, true, 1.0);
    g_cvarMysql = CreateConVar("sm_segfaultranks_mysql", "1", "Using MySQL? 1 = true 0 = false (SQLite currently not implemented)", _, true, 0.0, true, 1.0);
    g_cvarSQLTable = CreateConVar("sm_segfaultranks_sql_table", "segfaultranks", "The name of the table that will be used. (Max: 100)");

    AutoExecConfig(true, "segfaultranks", "sourcemod");

    //g_RWSCookie = RegClientCookie("segfaultranks_rws", "Segfault Ranks RWS rating", CookieAccess_Protected);
    //g_RoundsPlayedCookie = RegClientCookie("segfaultranks_roundsplayed", "Segfault Ranks rounds played", CookieAccess_Protected);
    //g_EloRankCookie = RegClientCookie("segfaultranks_elorank", "Segfault Ranks calculated elo value", CookieAccess_Protected);


    // Create the forwards
    g_fwdOnPlayerLoaded = CreateGlobalForward("SegfaultRanks_OnPlayerLoaded", ET_Hook, Param_Cell);
    g_fwdOnPlayerSaved = CreateGlobalForward("SegfaultRanks_OnPlayerSaved", ET_Hook, Param_Cell);
    g_hOnHelpCommand = CreateGlobalForward("SegfaultRanks_OnHelpCommand", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_CellByRef);
}

void GetCvarValues() {
    g_MinimumPlayers = g_cvarMinimumPlayers.IntValue;
    g_RankMode = g_cvarRankMode.IntValue;
    //g_DaysToNotShowOnRank = g_cvarDaysToNotShowOnRank.IntValue;
    g_MinimalRounds = g_cvarMinimalRounds.IntValue;
    g_bRankCache = g_cvarRankCache.BoolValue;
}

public void OnConfigsExecuted() {
    if (g_hStatsDb == INVALID_HANDLE)
        DB_Connect(true);
    else
        DB_Connect(false);
    int AutoPurge = g_cvarAutopurge.IntValue;
    char sQuery[1000];
    if (AutoPurge > 0) {
        int DeleteBefore = GetTime() - (AutoPurge * 86400);
        Format(sQuery, sizeof(sQuery), "DELETE FROM `%s` WHERE lastconnect < '%d'", g_sSQLTable, DeleteBefore);
        SQL_TQuery(g_hStatsDb, SQL_PurgeCallback, sQuery);
    }
    
    GetCvarValues();

    Format(sQuery, sizeof(sQuery), "SELECT * FROM `%s` WHERE rounds_total >= '%d' AND steam <> 'BOT'", g_sSQLTable, g_MinimalRounds);
    
    SQL_TQuery(g_hStatsDb, SQL_GetPlayersCallback, sQuery);

    CheckUnique();
    BuildRankCache();
}

void BuildRankCache()
{
    if(!g_bRankCache)
        return;
    
    ClearArray(g_steamRankCache);
    
    PushArrayString(g_steamRankCache, "Rank By SteamId: This is First Line in Array");
    
    char query[1000];
    MakeSelectQuery(query, sizeof(query));

    if (g_RankMode == 1){Format(query, sizeof(query), "%s ORDER BY rws DESC", query);}
    else if(g_RankMode == 2){Format(query, sizeof(query), "%s ORDER BY CAST(kills as DECIMAL)/CAST(Case when deaths=0 then 1 ELSE deaths END as DECIMAL) DESC", query);}
    else {Format(query, sizeof(query), "%s ORDER BY elo DESC", query);}
    
    SQL_TQuery(g_hStatsDb, SQL_BuildRankCache, query);
}

public void SQL_BuildRankCache(Handle owner, Handle hndl, const char[] error, any unuse)
{
    if (hndl == INVALID_HANDLE)
    {
        LogError("[RankMe] : build rank cache failed", error);
        return;
    }
    
    if(SQL_GetRowCount(hndl))
    {
        char steamid[32];
        while(SQL_FetchRow(hndl))
        {
            SQL_FetchString(hndl, 1, steamid, 32);
            PushArrayString(g_steamRankCache, steamid);
        }
    }
    else
        LogMessage("[RankMe] :  No mork rank");
}

stock void MakeSelectQuery(char[] sQuery, int strsize) {
    
    // Make basic query
    Format(sQuery, strsize, "SELECT * FROM `%s` WHERE rounds_total >= '%d'", g_sSQLTable, g_MinimalRounds);
    
    // Append check for inactivity
    //if (g_DaysToNotShowOnRank > 0)
    //    Format(sQuery, strsize, "%s AND lastconnect >= '%d'", sQuery, GetTime() - (g_DaysToNotShowOnRank * 86400));
} 

public void DB_Connect(bool firstload) {
    if(firstload) {
        g_bMysql = g_cvarMysql.BoolValue;
        g_cvarSQLTable.GetString(g_sSQLTable, sizeof(g_sSQLTable));
        char sError[256];
        if (g_bMysql) {
            g_hStatsDb = SQL_Connect("segfaultranks", false, sError, sizeof(sError));
        } else {
            //g_hStatsDb = SQLite_UseDatabase("segfaultranks", sError, sizeof(sError));
        }
        if (g_hStatsDb == INVALID_HANDLE)
        {
            SetFailState("[SegfaultRanks] Unable to connect to the database (%s)", sError);
        }
        SQL_LockDatabase(g_hStatsDb);
        char sQuery[9999];

        if(g_bMysql)
        {
            Format(sQuery, sizeof(sQuery), g_sMysqlCreate, g_sSQLTable);
            SQL_FastQuery(g_hStatsDb, sQuery);
        }
        if(!g_bMysql)
        {
            //Format(sQuery, sizeof(sQuery), g_sSqliteCreate, g_sSQLTable);
            //SQL_FastQuery(g_hStatsDb, sQuery);
        }


        // I suspect these were used to update an existing table (which we do not need to do yet, since ours is new):
        /*Format(sQuery, sizeof(sQuery), "ALTER TABLE `%s` MODIFY id INTEGER AUTO_INCREMENT", g_sSQLTable);
        SQL_FastQuery(g_hStatsDb, sQuery);

        Format(sQuery, sizeof(sQuery), "ALTER TABLE `%s` ADD COLUMN match_win NUMERIC", g_sSQLTable);
        SQL_FastQuery(g_hStatsDb, sQuery);
        Format(sQuery, sizeof(sQuery), "ALTER TABLE `%s` ADD COLUMN match_draw NUMERIC", g_sSQLTable);
        SQL_FastQuery(g_hStatsDb, sQuery);
        Format(sQuery, sizeof(sQuery), "ALTER TABLE `%s` ADD COLUMN match_lose NUMERIC", g_sSQLTable);
        SQL_FastQuery(g_hStatsDb, sQuery);
        Format(sQuery, sizeof(sQuery), "ALTER TABLE `%s` ADD COLUMN first_blood NUMERIC", g_sSQLTable);
        SQL_FastQuery(g_hStatsDb, sQuery);
        Format(sQuery, sizeof(sQuery), "ALTER TABLE `%s` ADD COLUMN no_scope NUMERIC", g_sSQLTable);
        SQL_FastQuery(g_hStatsDb, sQuery);
        Format(sQuery, sizeof(sQuery), "ALTER TABLE `%s` ADD COLUMN no_scope_dis NUMERIC", g_sSQLTable);
        SQL_FastQuery(g_hStatsDb, sQuery);
        Format(sQuery, sizeof(sQuery), "ALTER TABLE `%s` CHANGE steam steam VARCHAR(40)", g_sSQLTable);
        SQL_FastQuery(g_hStatsDb, sQuery);
        SQL_UnlockDatabase(g_hStatsDb);*/

        for (int i = 1; i <= MaxClients; i++) {
            if (IsClientInGame(i)) {
                ReloadClient(i);
            }
        }
    }
}

/*public void OnClientPutInServer(int client) {
    
    // If the database isn't connected, you can't run SQL_EscapeString.
    if (g_hStatsDb != INVALID_HANDLE){
        LoadPlayer(client);
    }
        
    // Cookie
    if(IsValidClient(client) && !IsFakeClient(client)){
        char buffer[5];
        GetClientCookie(client, hidechatcookie, buffer, sizeof(buffer));
        if(StrEqual(buffer, "") || StrEqual(buffer,"0")){hidechat[client] = false;}
        else if(StrEqual(buffer,"1")){hidechat[client] = true;}
    }
}*/

public void OnClientAuthorized(int client, const char[] auth) {
    ReloadClient(client);
}

void ReloadClient(int client) {
    if (g_hStatsDb != INVALID_HANDLE){
        LoadPlayer(client);
    }
}

public void LoadPlayer(int client) {

    OnDB[client] = false;
    // stats
    g_aStats[client].Reset();
    //g_aStats[client].SCORE = g_PointsStart;//default starting points (not needed for the RWS system)
    g_aSessionConnectedTime[client] = GetTime();
        
    char name[MAX_NAME_LENGTH];
    GetClientName(client, name, sizeof(name));
    strcopy(g_aClientName[client], MAX_NAME_LENGTH, name);
    char sEscapeName[MAX_NAME_LENGTH * 2 + 1];
    SQL_EscapeString(g_hStatsDb, name, sEscapeName, sizeof(sEscapeName));
    char auth[32];
    GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
    strcopy(g_aClientSteam[client], sizeof(g_aClientSteam[]), auth);
    char ip[32];
    GetClientIP(client, ip, sizeof(ip));
    strcopy(g_aClientIp[client], sizeof(g_aClientIp[]), ip);
    char query[10000];

    FormatEx(query, sizeof(query), g_sSqlRetrieveClient, g_sSQLTable, auth);

    if (DEBUGGING) {
        PrintToServer(query);
        LogError("%s", query);
    }
    if (g_hStatsDb != INVALID_HANDLE){
        SQL_TQuery(g_hStatsDb, SQL_LoadPlayerCallback, query, client);
    }
}

public void SQL_LoadPlayerCallback(Handle owner, Handle hndl, const char[] error, any client)
{
    if (!IsValidClient(client) || IsFakeClient(client)){
        LogError("[SegRanks] Client %i is not a valid client during SQL_LoadPlayerCallback", client);
        return;
    }

    if (hndl == INVALID_HANDLE)
    {
        LogError("[SegRanks] Load Player Fail: %s", error);
        return;
    }
    if (!IsClientInGame(client))
    {
        LogError("[SegRanks] Client %i is not in game yet during SQL_LoadPlayerCallback", client);
        return;
    }

    char auth[64];
    GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
    if (!StrEqual(auth, g_aClientSteam[client])){
        LogError("[SegRanks] Client %i stored auth %s not equal to current %s", client, g_aClientSteam[client], auth);
        return;
    }


    //static const char g_sMysqlCreate[] = "CREATE TABLE IF NOT EXISTS `%s` (id INTEGER PRIMARY KEY, steam TEXT, name TEXT, lastip TEXT, connected NUMERIC, lastconnected NUMERIC, elo NUMERIC, rws NUMERIC, rounds_total NUMERIC, rounds_won NUMERIC, kills NUMERIC, deaths NUMERIC, assists NUMERIC, suicides NUMERIC, teamkills NUMERIC, headshots NUMERIC, total_damage NUMERIC, mvp NUMERIC, matches_won NUMERIC, matches_lost NUMERIC, matches_tied NUMERIC) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci";
    if (SQL_HasResultSet(hndl) && SQL_FetchRow(hndl))
    {
        //Player infos
        g_aStats[client].ELO = SQL_FetchFloat(hndl, 6);
        g_aStats[client].RWS = SQL_FetchFloat(hndl, 7);
        g_aStats[client].ROUNDS_TOTAL = SQL_FetchInt(hndl, 8);
        LogError("[SegRanks] Client %i has results set! Rounds Total: %i", client, g_aStats[client].ROUNDS_TOTAL);
        g_aStats[client].ROUNDS_WON = SQL_FetchInt(hndl, 9);
        g_aStats[client].KILLS = SQL_FetchInt(hndl, 10);
        g_aStats[client].DEATHS = SQL_FetchInt(hndl, 11);
        g_aStats[client].ASSISTS = SQL_FetchInt(hndl, 12);
        g_aStats[client].SUICIDES = SQL_FetchInt(hndl, 13);
        g_aStats[client].TEAMKILLS = SQL_FetchInt(hndl, 14);
        g_aStats[client].HEADSHOTS = SQL_FetchInt(hndl, 15);
        g_aStats[client].TOTAL_DAMAGE = SQL_FetchInt(hndl, 16);
        g_aStats[client].MVP = SQL_FetchInt(hndl, 17);
        g_aStats[client].MATCHES_WON = SQL_FetchInt(hndl, 18);
        g_aStats[client].MATCHES_LOST = SQL_FetchInt(hndl, 19);
        g_aStats[client].MATCHES_TIED = SQL_FetchInt(hndl, 20);
        
    } else {
        LogError("[SegRanks] Client %i had no results set, trying to init a new set in db.", client);
        SegfaultRanks_MessageToAll("[SegRanks] Client %i had no results set, trying to init a new set in db.", client);
        char query[10000];
        char sEscapeName[MAX_NAME_LENGTH * 2 + 1];
        SQL_EscapeString(g_hStatsDb, g_aClientName[client], sEscapeName, sizeof(sEscapeName));

        //static const char g_sMysqlCreate[] = "CREATE TABLE IF NOT EXISTS `%s` (id INTEGER PRIMARY KEY, steam TEXT, name TEXT, lastip TEXT, connected NUMERIC, lastconnected NUMERIC, elo NUMERIC, rws NUMERIC, rounds_total NUMERIC, rounds_won NUMERIC, kills NUMERIC, deaths NUMERIC, assists NUMERIC, suicides NUMERIC, teamkills NUMERIC, headshots NUMERIC, total_damage NUMERIC, mvp NUMERIC, matches_won NUMERIC, matches_lost NUMERIC, matches_tied NUMERIC) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci";
        //static const char g_sSqlInitInsert[] = "INSERT INTO `%s` VALUES (NULL,'%s','%s','%s','0','0','500.0','0.0','0','0','0','0','0','0','0','0','0','0','0','0','0');";
        Format(query, sizeof(query), g_sSqlInitInsert, g_sSQLTable, g_aClientSteam[client], sEscapeName, g_aClientIp[client]);
        SQL_TQuery(g_hStatsDb, SQL_NothingCallback, query, _, DBPrio_High);

        if (DEBUGGING) {
            PrintToServer(query);
            LogError("%s", query);
        }
    }
    SegfaultRanks_MessageToAll("Player Now On DB %i", client);
    OnDB[client] = true;
    /**
    Start the forward OnPlayerLoaded
    **/
    Action fResult;
    Call_StartForward(g_fwdOnPlayerLoaded);
    Call_PushCell(client);
    int fError = Call_Finish(fResult);

    if (fError != SP_ERROR_NONE)
    {
        ThrowNativeError(fError, "Forward failed");
    }
}

public void SQL_PurgeCallback(Handle owner, Handle hndl, const char[] error, any client)
{
    if (hndl == INVALID_HANDLE)
    {
        LogError("[SegRank] Query Fail: %s", error);
        return;
    }

    PrintToServer("[SegRank]: %d players purged by inactivity", SQL_GetAffectedRows(owner));
    if (client != 0) {
        PrintToChat(client, "[SegRank]: %d players purged by inactivity", SQL_GetAffectedRows(owner));
    }
    //LogAction(-1,-1,"[RankMe]: %d players purged by inactivity",SQL_GetAffectedRows(owner));
}


public void SQL_NothingCallback(Handle owner, Handle hndl, const char[] error, any client)
{
    if (hndl == INVALID_HANDLE)
    {
        LogError("[SegRank] Query Fail: %s", error);
        return;
    }
}

public void OnPluginEnd() {
    if (!g_bEnabled){return;}
    SQL_LockDatabase(g_hStatsDb);
    for (int client = 1; client <= MaxClients; client++) {
        if (IsClientInGame(client)) {
            if (!IsValidClient(client) || IsFakeClient(client)){return;}
            char name[MAX_NAME_LENGTH];
            GetClientName(client, name, sizeof(name));
            char sEscapeName[MAX_NAME_LENGTH * 2 + 1];
            SQL_EscapeString(g_hStatsDb, name, sEscapeName, sizeof(sEscapeName));

            /* SM1.9 Fix */ // <-------- what the fuck does that even mean???? what exactly was fixed? was it a query character limit?
            char query[4000];

            //static const char g_sSqlSave[] = "UPDATE `%s` SET name='%s',lastip='%s',elo='%f',rws='%f',rounds_total='%i',rounds_won='%i',kills='%i',deaths='%i',assists='%i',suicides='%i',teamkills='%i',headshots='%i',total_damage='%i',mvp ='%i',matches_won='%i',matches_lost='%i',matches_tied='%s' WHERE steam = '%s';";
            Format(query, sizeof(query), g_sSqlSave, g_sSQLTable, sEscapeName, g_aClientIp[client], g_aStats[client].ELO, g_aStats[client].RWS, g_aStats[client].ROUNDS_TOTAL, g_aStats[client].ROUNDS_WON,
                g_aStats[client].KILLS, g_aStats[client].DEATHS, g_aStats[client].ASSISTS, g_aStats[client].SUICIDES, g_aStats[client].TEAMKILLS, g_aStats[client].HEADSHOTS, g_aStats[client].TOTAL_DAMAGE,
                g_aStats[client].MVP, g_aStats[client].MATCHES_WON, g_aStats[client].MATCHES_LOST, g_aStats[client].MATCHES_TIED, g_aClientSteam[client]);

            LogMessage(query);
            SQL_FastQuery(g_hStatsDb, query);

            /**
            Start the forward OnPlayerSaved
            */
            Action fResult;
            Call_StartForward(g_fwdOnPlayerSaved);
            Call_PushCell(client);
            int fError = Call_Finish(fResult);
            
            if (fError != SP_ERROR_NONE)
            {
                ThrowNativeError(fError, "Forward failed");
            }
        }
    }
    SQL_UnlockDatabase(g_hStatsDb);
}

public void SavePlayerData(int client) {
    // TODO: ADD CHECK FOR IF PLUGIN IS DISABLED THAT STILL TAKES INTO ACCOUNT SAVING THE DATA ONE LAST TIME
    if (!IsValidClient(client) || IsFakeClient(client)){return;}
    //check for if player has been initiated on the db yet
    if (!IsOnDb(client)){return;}

    char sEscapeName[MAX_NAME_LENGTH * 2 + 1];
    SQL_EscapeString(g_hStatsDb, g_aClientName[client], sEscapeName, sizeof(sEscapeName));
    
    char query[4000];

    //static const char g_sSqlSave[] = "UPDATE `%s` SET name='%s',lastip='%s',elo='%f',rws='%f',rounds_total='%i',rounds_won='%i',kills='%i',deaths='%i',assists='%i',suicides='%i',teamkills='%i',headshots='%i',total_damage='%i',mvp ='%i',matches_won='%i',matches_lost='%i',matches_tied='%s' WHERE steam = '%s';";
    Format(query, sizeof(query), g_sSqlSave, g_sSQLTable, sEscapeName, g_aClientIp[client], g_aStats[client].ELO, g_aStats[client].RWS, g_aStats[client].ROUNDS_TOTAL, g_aStats[client].ROUNDS_WON,
        g_aStats[client].KILLS, g_aStats[client].DEATHS, g_aStats[client].ASSISTS, g_aStats[client].SUICIDES, g_aStats[client].TEAMKILLS, g_aStats[client].HEADSHOTS, g_aStats[client].TOTAL_DAMAGE,
        g_aStats[client].MVP, g_aStats[client].MATCHES_WON, g_aStats[client].MATCHES_LOST, g_aStats[client].MATCHES_TIED, g_aClientSteam[client]);

    LogMessage(query);
    SQL_FastQuery(g_hStatsDb, query);

    SQL_TQuery(g_hStatsDb, SQL_SaveCallback, query, client, DBPrio_High);
       
    if (DEBUGGING) {
        PrintToServer(query);
        LogError("%s", query);
    }
}

public void SQL_SaveCallback(Handle owner, Handle hndl, const char[] error, any client)
{
    if (hndl == INVALID_HANDLE)
    {
        LogError("[SegRank] Save Player Fail: %s", error);
        return;
    }
    
    /**
        Start the forward OnPlayerSaved
    */
    Action fResult;
    Call_StartForward(g_fwdOnPlayerSaved);
    Call_PushCell(client);
    int fError = Call_Finish(fResult);
    
    if (fError != SP_ERROR_NONE)
    {
        ThrowNativeError(fError, "Forward failed");
    }
    
}

// Points Events
/**
 * These events update player "rounds points" for computing rws at the end of each round.
 */

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
  if (CheckIfWarmup()){return;}

  int victim = GetClientOfUserId(event.GetInt("userid"));
  int attacker = GetClientOfUserId(event.GetInt("attacker"));

  bool validAttacker = IsValidClient(attacker);
  bool validVictim = IsValidClient(victim);

  if (validAttacker && validVictim && HelpfulAttack(attacker, victim)) {
    g_aStats[attacker].ROUND_POINTS += 100;
  }
}

public Action Event_Bomb(Event event, const char[] name, bool dontBroadcast) {
    //  don't count warmup rounds towards RWS
    if (CheckIfWarmup()){return;}

    int client = GetClientOfUserId(event.GetInt("userid"));
    g_aStats[client].ROUND_POINTS += 50;
}

public Action Event_DamageDealt(Event event, const char[] name, bool dontBroadcast) {
  if (CheckIfWarmup()){return;}

  int attacker = GetClientOfUserId(event.GetInt("attacker"));
  int victim = GetClientOfUserId(event.GetInt("userid"));
  bool validAttacker = IsValidClient(attacker);
  bool validVictim = IsValidClient(victim);

  if (validAttacker && validVictim && HelpfulAttack(attacker, victim)) {
    int damage = event.GetInt("dmg_health");
    g_aStats[attacker].ROUND_POINTS += damage;
  }
}

public bool HelpfulAttack(int attacker, int victim) {
  if (!IsValidClient(attacker) || !IsValidClient(victim)) {
    return false;
  }
  int ateam = GetClientTeam(attacker);
  int vteam = GetClientTeam(victim);
  return ateam != vteam && attacker != victim;
}

/**
 * Round end event, updates rws values for everyone.
 */
public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
    if (!ShouldRank())
    {
        //reset round points here anyways so that they don't accidentaly affect the first real round TODO
        for (int i = 1; i <= MaxClients; i++) {
            if (IsPlayer(i) && IsOnDb(i)) {
                g_aStats[i].ROUND_POINTS = 0;
            }
        }
        return;
    }

    int winner = event.GetInt("winner");
    for (int i = 1; i <= MaxClients; i++) {
        if (IsPlayer(i) && IsOnDb(i)) {
            int team = GetClientTeam(i);
            if (team == CS_TEAM_CT || team == CS_TEAM_T){RWSUpdate(i, team == winner);}
        }
    }
    for (int i = 1; i <= MaxClients; i++) {
        if (IsPlayer(i) && IsOnDb(i)) {
            g_aStats[i].ROUND_POINTS = 0;
            SavePlayerData(i);
        }
    }
}

/**
 * Here we apply magic updates to a player's rws based on the previous round.
 */
static void RWSUpdate(int client, bool winner) {
  float rws = 0.0;
  if (winner) {
    int playerCount = 0;
    int sum = 0;
    for (int i = 1; i <= MaxClients; i++) {
      if (IsPlayer(i)) {
        if (GetClientTeam(i) == GetClientTeam(client)) {
          sum += g_aStats[i].ROUND_POINTS;
          playerCount++;
        }
      }
    }

    if (sum != 0) {
      // scaled so it's always considered "out of 5 players" so different team sizes
      // don't give inflated rws
      rws = 100.0 * float(playerCount) / 5.0 * float(g_aStats[client].ROUND_POINTS) / float(sum);
    } else {
      return;
    }

  } else {
    rws = 0.0;
  }

  float alpha = GetAlphaFactor(client);
  g_aStats[client].RWS = (1.0 - alpha) * g_aStats[client].RWS + alpha * rws;
  g_aStats[client].ROUNDS_TOTAL++;
  LogDebug("RoundUpdate(%L), alpha=%f, round_rws=%f, new_rws=%f", client, alpha, rws,
           g_aStats[client].RWS);
}



// some utils (TODO MOVE THIS TO UTIL FILE)

public bool IsOnDb(int client) {
  return OnDB[client];
}

// Re-Usable checks for wether or not we should rank players right now
bool ShouldRank() {
    // ranks should be calculated if it is not warmup, and there are at least the min player count (2 by default)
    // TODO: add check for if ranking is by round or by match either here or somewhere else
    return !CheckIfWarmup() && g_MinimumPlayers > GetCurrentPlayers();
}

// returns true if it is currently the warmup period
bool CheckIfWarmup() {
    return GameRules_GetProp("m_bWarmupPeriod") == 1;
}


static float GetAlphaFactor(int client) {
  float rounds = float(g_aStats[client].ROUNDS_TOTAL);
  if (rounds < ROUNDS_FINAL) {
    return ALPHA_INIT + (ALPHA_INIT - ALPHA_FINAL) / (-ROUNDS_FINAL) * rounds;
  } else {
    return ALPHA_FINAL;
  }
}

public int rwsSortFunction(int index1, int index2, Handle array, Handle hndl) {
  int client1 = GetArrayCell(array, index1);
  int client2 = GetArrayCell(array, index2);
  return g_aStats[client1].RWS < g_aStats[client2].RWS;
}

/*void SortPlayersLeaderboardTodo() {
    ArrayList players = new ArrayList();

    for (int i = 1; i <= MaxClients; i++) {
      if (IsPlayer(i))
        PushArrayCell(players, i);
    }

    SortADTArrayCustom(players, rwsSortFunction);

    if (players.Length >= 1)
      PugSetup_SetCaptain(1, GetArrayCell(players, 0));

    if (players.Length >= 2)
      PugSetup_SetCaptain(2, GetArrayCell(players, 1));

    delete players;
}*/


// Commands

public Action Command_DumpRWS(int client, int args) {
    for (int i = 1; i <= MaxClients; i++) {
        if (IsPlayer(i) && IsOnDb(i)) {
            ReplyToCommand(client, "%L has RWS=%f, roundsplayed=%d", i, g_aStats[i].RWS,g_aStats[i].ROUNDS_TOTAL);
        }
    }

    return Plugin_Handled;
}

public Action Command_RWS(int client, int args) {
  if (g_AllowStatsOtherCommandCvar.IntValue == 0) {
    return Plugin_Handled;
  }

  char arg1[32];
  if (args >= 1 && GetCmdArg(1, arg1, sizeof(arg1))) {
    int target = FindTarget(client, arg1, true, false);
    if (target != -1) {
      if (IsOnDb(target)) {
        SegfaultRanks_Message(client, "%N has a RWS of %.1f with %d rounds played", target, g_aStats[target].RWS, g_aStats[target].ROUNDS_TOTAL);
      }
      else {
        SegfaultRanks_Message(client, "%N does not currently have stats stored", target);
      }
    }
  } else {
    SegfaultRanks_Message(client, "Usage: .rws <player>");
  }

  return Plugin_Handled;
}

public Action Command_Rank(int client, int args) {
    return Plugin_Handled;
}

public Action Command_Leaderboard(int client, int args) {
    return Plugin_Handled;
}

/*public void PugSetup_OnPlayerAddedToCaptainMenu(Menu menu, int client, char[] menuString, int length) {
  if (g_ShowRWSOnMenuCvar.IntValue != 0 && HasStats(client)) {
    Format(menuString, length, "%N [%.1f RWS]", client, g_aStats[client].RWS);
  }
}*/


// Alias Commands

public void LoadTranslatedAliases() {
    // For each of these sm_x commands, we need the
    // translation phrase sm_x_alias to be present.
    //AddTranslatedAlias("sm_capt", ChatAlias_NoWarmup);
    //AddTranslatedAlias("sm_endgame", ChatAlias_NoWarmup);
    //AddTranslatedAlias("sm_notready", ChatAlias_NoWarmup);
    //AddTranslatedAlias("sm_pause", ChatAlias_NoWarmup);
    //AddTranslatedAlias("sm_ready", ChatAlias_NoWarmup);
    //AddTranslatedAlias("sm_setup");
    //AddTranslatedAlias("sm_stay", ChatAlias_NoWarmup);
    //AddTranslatedAlias("sm_swap", ChatAlias_NoWarmup);
    //AddTranslatedAlias("sm_unpause", ChatAlias_NoWarmup);
    //AddTranslatedAlias("sm_start", ChatAlias_NoWarmup);
}

public void LoadExtraAliases() {
    // Read custom user aliases
    //ReadChatConfig();
    
    // Any extra chat aliases we want
    SegfaultRanks_AddChatAlias(".segfault", "sm_rank", ChatAlias_NoWarmup);
    SegfaultRanks_AddChatAlias(".stats", "sm_rws", ChatAlias_NoWarmup);
    SegfaultRanks_AddChatAlias(".rws", "sm_rws", ChatAlias_NoWarmup);
    SegfaultRanks_AddChatAlias(".rank", "sm_rank", ChatAlias_NoWarmup);
    SegfaultRanks_AddChatAlias(".top", "sm_top", ChatAlias_NoWarmup);
    SegfaultRanks_AddChatAlias(".leaderboard", "sm_top", ChatAlias_NoWarmup);
}

/*static void AddTranslatedAlias(const char[] command, ChatAliasMode mode = ChatAlias_Always) {
    char translationName[128];
    Format(translationName, sizeof(translationName), "%s_alias", command);
    
    char alias[ALIAS_LENGTH];
    Format(alias, sizeof(alias), "%T", translationName, LANG_SERVER);
    
    SegfaultRanks_AddChatAlias(alias, command, mode);
}*/

public bool FindAliasFromCommand(const char[] command, char alias[ALIAS_LENGTH]) {
    int n = g_ChatAliases.Length;
    char tmpCommand[COMMAND_LENGTH];
    
    for (int i = 0; i < n; i++) {
        g_ChatAliasesCommands.GetString(i, tmpCommand, sizeof(tmpCommand));
        
        if (StrEqual(command, tmpCommand)) {
            g_ChatAliases.GetString(i, alias, sizeof(alias));
            return true;
        }
    }
    
    // If we never found one, just use .<command> since it always gets added by AddPugSetupCommand
    Format(alias, sizeof(alias), ".%s", command);
    return false;
}

public bool FindComandFromAlias(const char[] alias, char command[COMMAND_LENGTH]) {
    int n = g_ChatAliases.Length;
    char tmpAlias[ALIAS_LENGTH];
    
    for (int i = 0; i < n; i++) {
        g_ChatAliases.GetString(i, tmpAlias, sizeof(tmpAlias));
        
        if (StrEqual(alias, tmpAlias, false)) {
            g_ChatAliasesCommands.GetString(i, command, sizeof(command));
            return true;
        }
    }
    
    return false;
}

static bool CheckChatAlias(const char[] alias, const char[] command, const char[] chatCommand, 
    const char[] chatArgs, int client, ChatAliasMode mode) {
    if (StrEqual(chatCommand, alias, false)) {
        if (mode == ChatAlias_NoWarmup && CheckIfWarmup()) {
            return false;
        }
        
        // Get the original cmd reply source so it can be restored after the fake client command.
        // This means and ReplyToCommand will go into the chat area, rather than console, since
        // *chat* aliases are for *chat* commands.
        ReplySource replySource = GetCmdReplySource();
        SetCmdReplySource(SM_REPLY_TO_CHAT);
        char fakeCommand[256];
        Format(fakeCommand, sizeof(fakeCommand), "%s %s", command, chatArgs);
        FakeClientCommand(client, fakeCommand);
        SetCmdReplySource(replySource);
        return true;
    }
    return false;
}

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs) {
    if (!IsPlayer(client))
        return;
    
    // splits to find the first word to do a chat alias command check
    char chatCommand[COMMAND_LENGTH];
    char chatArgs[255];
    int index = SplitString(sArgs, " ", chatCommand, sizeof(chatCommand));
    
    if (index == -1) {
        strcopy(chatCommand, sizeof(chatCommand), sArgs);
    } else if (index < strlen(sArgs)) {
        strcopy(chatArgs, sizeof(chatArgs), sArgs[index]);
    }
    
    if (chatCommand[0]) {
        char alias[ALIAS_LENGTH];
        char cmd[COMMAND_LENGTH];
        for (int i = 0; i < GetArraySize(g_ChatAliases); i++) {
            GetArrayString(g_ChatAliases, i, alias, sizeof(alias));
            GetArrayString(g_ChatAliasesCommands, i, cmd, sizeof(cmd));
            if (CheckChatAlias(alias, cmd, chatCommand, chatArgs, client, g_ChatAliasesModes.Get(i))) {
                break;
            }
        }
    }
    
    if (StrEqual(sArgs[0], ".help")) {
        const int msgSize = 128;
        ArrayList msgs = new ArrayList(msgSize);
        
        msgs.PushString("{PURPLE}.stats {NORMAL}displays your stats");
        msgs.PushString("{PURPLE}.top {NORMAL}shows the leaderboard");
        msgs.PushString("{PURPLE}.rank {NORMAL}see your current ranking");
        msgs.PushString("{PURPLE}.segfault {NORMAL}cause a segmentation violation");
        
        bool block = false;
        Call_StartForward(g_hOnHelpCommand);
        Call_PushCell(client);
        Call_PushCell(msgs);
        Call_PushCell(msgSize);
        Call_PushCellRef(block);
        Call_Finish();
        
        if (!block) {
            char msg[msgSize];
            for (int i = 0; i < msgs.Length; i++) {
                msgs.GetString(i, msg, sizeof(msg));
                SegfaultRanks_Message(client, msg);
            }
        }
        
        delete msgs;
    }
    
    // Allow using .map as a map-vote revote alias and as a
    // shortcut to the mapchange menu (if avaliable).
    /*if (StrEqual(sArgs, ".map") || StrEqual(sArgs, "!revote")) {
        if (IsVoteInProgress() && IsClientInVotePool(client)) {
            RedrawClientVoteMenu(client);
        } else if (g_IRVActive) {
            ResetClientVote(client);
            ShowInstantRunoffMapVote(client, 0);
        } else if (PugSetup_IsPugAdmin(client) && g_DisplayMapChange) {
            PugSetup_GiveMapChangeMenu(client);
        }
    }*/
}