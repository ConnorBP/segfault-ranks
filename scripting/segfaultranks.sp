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


//#define AUTH_METHOD AuthId_Steam2

//forwards

Handle g_fwdOnPlayerLoaded = INVALID_HANDLE;
Handle g_fwdOnPlayerSaved = INVALID_HANDLE;

Handle g_hOnHelpCommand = INVALID_HANDLE;

bool g_bEnabled = true; //TODO add a convar to disable this plugin, and verify that the database is handles properly when the plugin is disabled while already running

// User Data Cache

// Local cache of state user stats
UserData userData[MAXPLAYERS + 1];

// convar local variables

//minimum players required for ranks to calculate
int g_MinimumPlayers = 2;
int g_RankMode = 1;
//int g_DaysToNotShowOnRank;
int g_MinimalRounds = 0;
bool g_bRankCache = false;


//Convars

ConVar g_MessagePrefixCvar;

ConVar g_AllowStatsOtherCommandCvar;
//ConVar g_RecordStatsCvar;
//ConVar g_cvarAutopurge;
ConVar g_cvarMinimumPlayers;
ConVar g_cvarRankMode;
//ConVar g_cvarDaysToNotShowOnRank;
ConVar g_cvarMinimalRounds;
ConVar g_cvarRankCache;
//ConVar g_RankEachRoundCvar;
//ConVar g_SetEloRanksCvar;
//ConVar g_ShowRWSOnScoreboardCvar
//ConVar g_ShowRankOnScoreboardCvar;




#include "segfaultranks/natives.sp"

public Plugin myinfo = {
    name = "CS:GO RWS Ranking System",
    author = "segfault",
    description = "Keeps track of user rankings based on an RWS Elo system",
    version = PLUGIN_VERSION,
    url = "https://segfault.club"
};


public void OnPluginStart() {
    //g_cvarDebugEnabled = CreateConvar(DEBUG_CVAR, "segfaultranks", "is segfaultranks debugging filename?");
    InitDebugLog(DEBUG_CVAR, "segfaultranks");
    //LoadTranslations("segfaultranks.phrases");
    LoadTranslations("common.phrases");

    // Initiate the rankings cache Global Adt Array
    g_steamRankCache = CreateArray(ByteCountToCells(128));

    DB_Init_Stuff();

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
    //g_cvarAutopurge = CreateConVar("sm_segfaultranks_autopurge", "0", "Auto-Purge inactive players? X = Days  0 = Off", _, true, 0.0);
    g_cvarMinimumPlayers = CreateConVar("sm_segfaultranks_minimumplayers", "2", "Minimum players to start giving points", _, true, 0.0);
    g_cvarRankMode = CreateConVar("sm_segfaultrank_rank_mode", "1", "Rank by what? 1 = by rws 2 = by kdr 3 = by elo", _, true, 1.0, true, 3.0);
    //g_cvarDaysToNotShowOnRank = CreateConVar("sm_segfaultrank_timeout_days", "0", "Days inactive to not be shown on rank? X = days 0 = off", _, true, 0.0);
    g_cvarMinimalRounds = CreateConVar("sm_segfaultrank_minimal_rounds", "0", "Minimal rounds played for rank to be displayed", _, true, 0.0);
    //g_RankEachRoundCvar = CreateConVar("sm_segfaultranks_rank_rounds", "1", "Sets if Elo ranks should be updated every round instead of at match end. (Useful for retake ranking)");
    //g_SetEloRanksCvar = CreateConVar("sm_segfaultranks_display_elo_ranks", "2", "Wether or not to display user ranks based on calculated total ELO. (S,G,A,B,etc) 0=Don't Display 1=Calculate elo ranks 2=Use top RWS", _, true, 0.0, true, 2.0);
    //g_ShowRWSOnScoreboardCvar = CreateConVar("sm_segfaultranks_display_rws", "1", "Whether rws stats for current map are to be displayed on the ingame scoreboard in place of points.");
    //g_ShowRankOnScoreboardCvar = CreateConVar("sm_segfaultranks_display_rank", "1", "Whether rws stats for current map are to be displayed on the ingame scoreboard in place of points.");
    g_cvarRankCache = CreateConVar("sm_segfaultranks_rank_cache", "0", "Get player rank via cache, auto build cache on every OnMapStart.", _, true, 0.0, true, 1.0);

    AutoExecConfig(true, "segfaultranks", "sourcemod");

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

void DB_Init_Stuff() {

}

public void OnConfigsExecuted() {
    GetCvarValues();
    DB_Init_Stuff();
}

void BuildRankCache()
{

}


public void DB_Connect() {
    
}


public void OnClientPostAdminCheck(int client) {
    LogDebug("OnClientPostAdminCheck: %i", client);
    ReloadClient(client);
}

void ReloadClient(int client) {
    if (g_hStatsDb != INVALID_HANDLE){
        LogDebug("Client %i in reloadclient db handle is valid!", client);
        LoadPlayer(client);
    } else {
        LogDebug("Client %i in reloadclient db handle is invalid!", client);
    }
}

public void LoadPlayer(int client) {

    userData[client].on_db = false;
    // stats
    userData[client].Reset();

    LogDebug("Client %i connect time: %i", client, g_aSessionConnectedTime[client]);
    
    char name[MAX_NAME_LENGTH];
    GetClientName(client, name, sizeof(name));
    ReplaceString(name, sizeof(name), "'", "");

    strcopy(g_aClientName[client], MAX_NAME_LENGTH, name);

    char auth[32];
    GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
    strcopy(g_aClientSteam[client], sizeof(g_aClientSteam[]), auth);

    LogDebug("Added client %i auth id %s from received %s", client, g_aClientSteam[client], auth);

    
}


public void OnPluginEnd() {
    if (!g_bEnabled){return;}
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
    userData[attacker].ROUND_POINTS += 100;
  }
}

public Action Event_Bomb(Event event, const char[] name, bool dontBroadcast) {
    //  don't count warmup rounds towards RWS
    if (CheckIfWarmup()){return;}

    int client = GetClientOfUserId(event.GetInt("userid"));
    userData[client].ROUND_POINTS += 50;
}

public Action Event_DamageDealt(Event event, const char[] name, bool dontBroadcast) {
  if (CheckIfWarmup()){return;}

  int attacker = GetClientOfUserId(event.GetInt("attacker"));
  int victim = GetClientOfUserId(event.GetInt("userid"));
  bool validAttacker = IsValidClient(attacker);
  bool validVictim = IsValidClient(victim);

  if (validAttacker && validVictim && HelpfulAttack(attacker, victim)) {
    int damage = event.GetInt("dmg_health");
    userData[attacker].ROUND_POINTS += damage;
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
                userData[i].ROUND_POINTS = 0;
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
            userData[i].ROUND_POINTS = 0;
            SavePlayerData(i);
        }
    }
}

/**
 * Here we apply magic updates to a player's rws based on the previous round.
 */
static void RWSUpdate(int client, bool winner) {
    //todo make minimumEnemies a cvar
    #define minimumEnemies 1
    int totalPlayers = 0;
    int teamPlayers = 0;
    int sum = 0;
    for (int i = 1; i <= MaxClients; i++) {
      if (IsPlayer(i)) {
          totalPlayers++;
        if (GetClientTeam(i) == GetClientTeam(client)) {
          sum += userData[i].ROUND_POINTS;
          teamCount++;
        }
      }
    }

    if (teamCount > 0 && totalPlayers - teamCount >= minimumEnemies) {

      rws = update_on_server();
      localRws cache = serverRws
      localRoundsPlayed = serverROunds

    } else {
      return;
    }



  float alpha = GetAlphaFactor(client);
  userData[client].RWS = (1.0 - alpha) * userData[client].RWS + alpha * rws;
  userData[client].ROUNDS_TOTAL++;
  LogDebug("RoundUpdate(%L), alpha=%f, round_rws=%f, new_rws=%f", client, alpha, rws,
           userData[client].RWS);
}

void SetClientScoreboard(int client, int value) {
    CS_SetClientContributionScore(client, value);
}


// some utils (TODO MOVE THIS TO UTIL FILE)

public bool IsOnDb(int client) {
  return userData[client].on_db;
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



//handled on server
/*static float GetAlphaFactor(int client) {
  float rounds = float(userData[client].ROUNDS_TOTAL);
  if (rounds < ROUNDS_FINAL) {
    return ALPHA_INIT + (ALPHA_INIT - ALPHA_FINAL) / (-ROUNDS_FINAL) * rounds;
  } else {
    return ALPHA_FINAL;
  }
}*/


// Commands

public Action Command_DumpRWS(int client, int args) {
    for (int i = 1; i <= MaxClients; i++) {
        if (IsPlayer(i) && IsOnDb(i)) {
            ReplyToCommand(client, "%L has RWS=%f, roundsplayed=%d", i, userData[i].RWS,userData[i].ROUNDS_TOTAL);
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
        SegfaultRanks_Message(client, "%N has a RWS of %.1f with %d rounds played", target, userData[target].RWS, userData[target].ROUNDS_TOTAL);
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
    Format(menuString, length, "%N [%.1f RWS]", client, userData[client].RWS);
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