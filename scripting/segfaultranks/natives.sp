
#define ALIAS_LENGTH 64
#define COMMAND_LENGTH 64

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
    g_ChatAliases = new ArrayList(ALIAS_LENGTH);
    g_ChatAliasesCommands = new ArrayList(COMMAND_LENGTH);
    g_ChatAliasesModes = new ArrayList();

    CreateNative("SegfaultRanks_Message", Native_Message);
    CreateNative("SegfaultRanks_MessageToAll", Native_MessageToAll);
    CreateNative("SegfaultRanks_AddChatAlias", Native_AddChatAlias);
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
  cvarMessagePrefix.GetString(prefix, sizeof(prefix));

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
  cvarMessagePrefix.GetString(prefix, sizeof(prefix));
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
