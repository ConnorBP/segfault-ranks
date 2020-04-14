
//Data required for submitting new round:
/*
pub struct RoundData {
    steam_id: String,
    did_win: bool,
    round_points: i32,
    team_points: i32,
    team_count: i32,
}
*/


// Gets user stats from db using steamid and name, and initiates user if they don't already exist on db
void InitDbClientBySteam(int client) {
    if (GetFeatureStatus(FeatureType_Native, "SteamWorks_CreateHTTPRequest") == FeatureStatus_Available) {
        Handle authRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, url);
        if (authRequest == INVALID_HANDLE) {
            LogError("Failed to create HTTP request using url: %s", url);
            return;
        }

        SteamWorks_SetHTTPCallbacks(authRequest, SteamWorks_OnMapRecieved);
        SteamWorks_SetHTTPRequestContextValue(authRequest, replyToSerial, replySource);
        SteamWorks_SetHTTPRequestGetOrPostParameter(authRequest, "user", username);
        SteamWorks_SetHTTPRequestGetOrPostParameter(authRequest, "password", password);
        SteamWorks_SendHTTPRequest(authRequest);

    } else {
        LogError("You must have either the SteamWorks extension installed to run segfaultranks");
        SetFailState("Cannot start segfault stats without steamworks extension.");
    }
}

// if the user already has a known database id, then we can easily refresh their stats with this
void LoadDbClientById(int client) {

}



// Callback functions

public int SteamWorks_OnAuthRecieved(Handle request, bool failure, bool requestSuccessful,
                                    EHTTPStatusCode statusCode, int serial, ReplySource replySource) {
    if (failure || !requestSuccessful) {
        LogError("API request failed, HTTP status code = %d", statusCode);
        CheckMapChange();
        return;
    }

    SteamWorks_WriteHTTPResponseBodyToFile(request, g_DataFile);

    if (statusCode == k_EHTTPStatusCode200OK) {
        ReadMapFromDatafile();
        PrintToServer("Got new MOTW: %s", g_CurrentMOTW);
        if (serial != 0) {
            int client = GetClientFromSerial(serial);
            // Save original reply source to restore later.
            ReplySource r = GetCmdReplySource();
            SetCmdReplySource(replySource);
            ReplyToCommand(client, "Got new MOTW: %s", g_CurrentMOTW);
            SetCmdReplySource(r);
        }
    } else if (statusCode == k_EHTTPStatusCode400BadRequest) {
        char errMsg[1024];
        File f = OpenFile(g_DataFile, "r");
        if (f != null) {
            f.ReadLine(errMsg, sizeof(errMsg));
            delete f;
            LogError("Error message: %s", errMsg);
        }
        g_DefaultCvar.GetString(g_CurrentMOTW, sizeof(g_CurrentMOTW));
    }

    CheckMapChange();
}

public int SteamWorks_OnUserRecieved(Handle request, bool failure, bool requestSuccessful,
                                    EHTTPStatusCode statusCode, int serial) {
    if (failure || !requestSuccessful) {
        LogError("API request failed, HTTP status code = %d", statusCode);
        CheckMapChange();
        return;
    }

    char responseBody[256];
    SteamWorks_GetHTTPResponseBodyData(request, responseBody, sizeof(responseBody[]));

    if (statusCode == k_EHTTPStatusCode200OK) {
        if (serial != 0) {
            int client = GetClientFromSerial(serial);
            PrintToServer("Got new stats for client: %i serial: %i", client, serial);
            // parse data from json and save if it is all valid
            JSON_Object obj = json_decode(responseBody);
            float rws = obj.GetFloat("rws");
        }
    } else if (statusCode == k_EHTTPStatusCode400BadRequest || statusCode == k_EHTTPStatusCode404NotFound) {
        if (responseBody.length() > 0) {
            LogError("Error message: %s", responseBody);
        }
        g_DefaultCvar.GetString(g_CurrentMOTW, sizeof(g_CurrentMOTW));
    }

    CheckMapChange();
}