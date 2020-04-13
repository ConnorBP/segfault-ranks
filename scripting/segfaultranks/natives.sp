
#define ALIAS_LENGTH 64
#define COMMAND_LENGTH 64

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
    g_ChatAliases = new ArrayList(ALIAS_LENGTH);
    g_ChatAliasesCommands = new ArrayList(COMMAND_LENGTH);
    g_ChatAliasesModes = new ArrayList();

    CreateNative("SegfaultRanks_Message", Native_Message);
    CreateNative("SegfaultRanks_MessageToAll", Native_MessageToAll);
    CreateNative("SegfaultRanks_AddChatAlias", Native_AddChatAlias);
    CreateNative("SegfaultRanks_GetRank", Native_GetRank);
}


public int Native_AddChatAlias(Handle plugin, int numParams) {
  char alias[ALIAS_LENGTH];
  char command[COMMAND_LENGTH];
  GetNativeString(1, alias, sizeof(alias));
  GetNativeString(2, command, sizeof(command));

  ChatAliasMode mode = ChatAlias_Always;
  if (numParams >= 3) {
    mode = GetNativeCell(3);
  }

  // don't allow duplicate aliases to be added
  if (g_ChatAliases.FindString(alias) == -1) {
    g_ChatAliases.PushString(alias);
    g_ChatAliasesCommands.PushString(command);
    g_ChatAliasesModes.Push(mode);
  }
}

public int Native_Message(Handle plugin, int numParams) {
  int client = GetNativeCell(1);
  if (client != 0 && (!IsClientConnected(client) || !IsClientInGame(client)))
    return;

  char buffer[1024];
  int bytesWritten = 0;
  SetGlobalTransTarget(client);
  FormatNativeString(0, 2, 3, sizeof(buffer), bytesWritten, buffer);

  char prefix[64];
  g_MessagePrefixCvar.GetString(prefix, sizeof(prefix));

  char finalMsg[1024];
  if (StrEqual(prefix, ""))
    Format(finalMsg, sizeof(finalMsg), " %s", buffer);
  else
    Format(finalMsg, sizeof(finalMsg), "%s %s", prefix, buffer);

  if (client == 0) {
    Colorize(finalMsg, sizeof(finalMsg), false);
    PrintToConsole(client, finalMsg);
  } else if (IsClientInGame(client)) {
    Colorize(finalMsg, sizeof(finalMsg));
    PrintToChat(client, finalMsg);
  }
}

public int Native_MessageToAll(Handle plugin, int numParams) {
  char prefix[64];
  g_MessagePrefixCvar.GetString(prefix, sizeof(prefix));
  char buffer[1024];
  int bytesWritten = 0;

  for (int i = 0; i <= MaxClients; i++) {
    if (i != 0 && (!IsClientConnected(i) || !IsClientInGame(i)))
      continue;

    SetGlobalTransTarget(i);
    FormatNativeString(0, 1, 2, sizeof(buffer), bytesWritten, buffer);

    char finalMsg[1024];
    if (StrEqual(prefix, ""))
      Format(finalMsg, sizeof(finalMsg), " %s", buffer);
    else
      Format(finalMsg, sizeof(finalMsg), "%s %s", prefix, buffer);

    if (i != 0) {
      Colorize(finalMsg, sizeof(finalMsg));
      PrintToChat(i, finalMsg);
    } else {
      Colorize(finalMsg, sizeof(finalMsg), false);
      PrintToConsole(i, finalMsg);
    }
  }
}

public int Native_GetRank(Handle plugin, int numParams)
{
  int client = GetNativeCell(1);
  Function callback = GetNativeCell(2);
  any data = GetNativeCell(3);
  
  Handle pack = CreateDataPack();
  
  WritePackCell(pack, client);
  WritePackFunction(pack, callback);
  WritePackCell(pack, data);
  WritePackCell(pack, view_as<int>(plugin));
  
  if(g_bRankCache)
  {
    GetClientRank(pack);
    return;
  }

  char query[10000];
  MakeSelectQuery(query, sizeof(query));
  
  if (g_RankMode == 1)
  {
    Format(query, sizeof(query), "%s ORDER BY rws DESC", query);
  }
  else if (g_RankMode == 2)
  {
    Format(query, sizeof(query), "%s ORDER BY CAST(CAST(kills as float)/CAST (deaths as float) as float) DESC", query);
  }
  else
  {
    Format(query, sizeof(query), "%s ORDER BY elo DESC", query);
  }
  
  SQL_TQuery(g_hStatsDb, SQL_GetRankCallback, query, pack);
}

public void SQL_GetRankCallback(Handle owner, Handle hndl, const char[] error, any data)
{
  Handle pack = data;
  ResetPack(pack);
  int client = ReadPackCell(pack);
  Function callback = ReadPackFunction(pack);
  any args = ReadPackCell(pack);
  Handle plugin = ReadPackCell(pack);
  CloseHandle(pack);
  
  if (hndl == INVALID_HANDLE)
  {
    LogError("[SegRank] Query Fail: %s", error);
    CallRankCallback(0, 0, callback, 0, plugin);
    return;
  }
  int i;
  //g_TotalPlayers = SQL_GetRowCount(hndl);
  
  char Receive[64];
  
  while (SQL_HasResultSet(hndl) && SQL_FetchRow(hndl))
  {
    i++;
    SQL_FetchString(hndl, 1, Receive, sizeof(Receive));
    if (StrEqual(Receive, g_aClientSteam[client], false))
    {
      CallRankCallback(client, i, callback, args, plugin);
      break;
    }

  }
}

public void SQL_GetPlayersCallback(Handle owner, Handle hndl, const char[] error, any Datapack){
    if(hndl == INVALID_HANDLE)
    {
        LogError("[SegRank] Query Fail: %s", error);
        PrintToServer(error);
        return;
    }
    //g_TotalPlayers = SQL_GetRowCount(hndl);
}

void CheckUnique(){
    char sQuery[1000];
    //if(g_bMysql){
    Format(sQuery, sizeof(sQuery), "SHOW INDEX FROM `%s` WHERE Key_name = 'steam'", g_sSQLTable);
    //}
    //else{Format(sQuery, sizeof(sQuery), "PRAGMA INDEX_LIST('%s')", g_sSQLTable);}
    SQL_TQuery(g_hStatsDb, SQL_SetUniqueCallback, sQuery);
}

public void SQL_SetUniqueCallback(Handle owner, Handle hndl, const char[] error, any Datapack){
    if (hndl == INVALID_HANDLE)
    {
        LogError("[RankMe] Check Unique Key Fail: %s", error);
        return;
    }

    char sQuery[1000];

    Format(sQuery, sizeof(sQuery), "DELETE FROM `%s` WHERE steam = 'BOT'" ,g_sSQLTable);
    SQL_TQuery(g_hStatsDb, SQL_NothingCallback, sQuery);
    // check unique key is exists or not
    if(SQL_GetRowCount(hndl) < 1){
        //if(g_bMysql){
        Format(sQuery, sizeof(sQuery), "ALTER TABLE `%s` ADD UNIQUE(steam)" ,g_sSQLTable);
        //  }
        //else{Format(sQuery, sizeof(sQuery), "CREATE UNIQUE INDEX steam ON `%s`(steam)" ,g_sSQLTable);}
        SQL_TQuery(g_hStatsDb, SQL_NothingCallback, sQuery);
    }
}

void GetClientRank(Handle pack)
{
  ResetPack(pack);
  int client = ReadPackCell(pack);
  Function callback = ReadPackFunction(pack);
  any args = ReadPackCell(pack);
  Handle plugin = ReadPackCell(pack);
  CloseHandle(pack);
  
  int rank;

  char steamid[32];
  GetClientAuthId(client, AuthId_Steam2, steamid, 32, true);
  rank = FindStringInArray(g_steamRankCache, steamid);

  if(rank > 0) {
    CallRankCallback(client, rank, callback, args, plugin);
  }
  else
  {
    CallRankCallback(client, 0, callback, args, plugin);
  }
}

void CallRankCallback(int client, int rank, Function callback, any data, Handle plugin)
{
  Call_StartFunction(plugin, callback);
  Call_PushCell(client);
  Call_PushCell(rank);
  Call_PushCell(data);
  Call_Finish();
  CloseHandle(plugin);
}