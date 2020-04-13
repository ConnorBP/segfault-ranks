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