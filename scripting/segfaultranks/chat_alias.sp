// Alias Commands

// Permission checking values.
enum Permission {
  Permission_All,       // anyone can use the command
  Permission_Captains,  // only captains (and higher) can use the command (note: reverts to
                        // Permission_All when not using captains)
  Permission_Leader,    // only the pug leader (and higher) can use the command
  Permission_Admin,     // only pug admins can use the command
  Permission_None,      // this command is disabled
};

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
    SegfaultRanks_AddChatAlias(".top", "sm_leaderboard", ChatAlias_Always);
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


