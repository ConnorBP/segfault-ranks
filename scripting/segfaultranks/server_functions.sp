
//#define BASE_API_URL "http://localhost:1337/v1"
#define BASE_API_URL baseApiUrl
#define NEW_ROUND "newround"
#define USER_INIT "userinit"

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

/*

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

}*/

// Sends a steam id and name to the server, if it exists it returns the stats to our callback, if not it creats a new user on the db and returns its new stats
bool InitUser(int client) {
    char url[128];
    Format(url, sizeof(url), "%s/%s", BASE_API_URL, USER_INIT);

    Handle initRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, url);
    if (initRequest == INVALID_HANDLE) {
        LogError("Failed to create HTTP request using url: %s", url);
        return false;
    }

    SteamWorks_SetHTTPCallbacks(initRequest, SteamWorks_OnUserReceived);
    SteamWorks_SetHTTPRequestContextValue(initRequest, GetClientSerial(client));
    SteamWorks_SetHTTPRequestGetOrPostParameter(initRequest, "steam_id", userData[client].steamid2);
    SteamWorks_SetHTTPRequestGetOrPostParameter(initRequest, "display_name", userData[client].display_name);

    /*
    Triggers a HTTPRequestCompleted_t callback.
    Returns true upon successfully setting the parameter.
    Returns false under the following conditions:
    hRequest was invalid.
    The request has already been sent.
    pCallHandle is NULL.
    */
    return SteamWorks_SendHTTPRequest(initRequest);
}

// Submits a round to the server. Returns true regardless of if the round actually updates on the server. Returns false if some failure happens trying to send it.
// actual handling of if the submission was successful is on the callback function
bool SendNewRound(int client, bool did_win, int round_points, int team_points, int team_count) {
    char url[128];
    Format(url, sizeof(url), "%s/%s", BASE_API_URL, NEW_ROUND);

    Handle authRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, url);
    if (authRequest == INVALID_HANDLE) {
        LogError("Failed to create HTTP request using url: %s", url);
        return false;
    }

    SteamWorks_SetHTTPCallbacks(authRequest, SteamWorks_OnNewRoundSent);
    SteamWorks_SetHTTPRequestContextValue(authRequest, GetClientSerial(client));
    SteamWorks_SetHTTPRequestGetOrPostParameter(authRequest, "steam_id", userData[client].steamid2);
    if(did_win) {
        //hacky boolToStr cause fuck sourcepawn
        SteamWorks_SetHTTPRequestGetOrPostParameter(authRequest, "did_win", "true");
    } else {
        SteamWorks_SetHTTPRequestGetOrPostParameter(authRequest, "did_win", "false");
    }
    char strRoundPoints[32];
    IntToString(round_points, strRoundPoints, sizeof(strRoundPoints));
    SteamWorks_SetHTTPRequestGetOrPostParameter(authRequest, "round_points", strRoundPoints);
    char strTeamPoints[32];
    IntToString(team_points, strTeamPoints, sizeof(strTeamPoints));
    SteamWorks_SetHTTPRequestGetOrPostParameter(authRequest, "team_points", strTeamPoints);
    char strTeamCount[32];
    IntToString(team_count, strTeamCount, sizeof(strTeamCount));
    SteamWorks_SetHTTPRequestGetOrPostParameter(authRequest, "team_count", strTeamCount);
    /*
    Triggers a HTTPRequestCompleted_t callback.
    Returns true upon successfully setting the parameter.
    Returns false under the following conditions:
    hRequest was invalid.
    The request has already been sent.
    pCallHandle is NULL.
    */
    return SteamWorks_SendHTTPRequest(authRequest);
}



// Callback functions
/*
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

}

public int SteamWorks_OnUserRecieved(Handle request, bool failure, bool requestSuccessful,EHTTPStatusCode statusCode, int serial) {
    if (failure || !requestSuccessful) {
        LogError("API request failed, HTTP status code = %d", statusCode);

        return;
    }

    char responseBody[1024];
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
    }
}*/

public int SteamWorks_OnUserReceived(Handle request, bool failure, bool requestSuccessful, EHTTPStatusCode statusCode, int serial) {
    if (failure || !requestSuccessful) {
        LogError("API request failed, HTTP status code = %d", statusCode);
        return;
    }

    char responseBody[1024];
    SteamWorks_GetHTTPResponseBodyData(request, responseBody, sizeof(responseBody));

    if (statusCode == k_EHTTPStatusCode200OK) {
        if (serial != 0) {
            int client = GetClientFromSerial(serial);
            userData[client].on_db = true;
            PrintToServer("Client %i was successfully loaded in the database!", client);
            PrintToServer("Got response: %s", responseBody);//temporary
            //TODO: parse returned json and update local variables (such as round count)
        }
    } /*else if (statusCode == k_EHTTPStatusCode400BadRequest || statusCode == k_EHTTPStatusCode404NotFound) {
        if (responseBody.length() > 0) {
            LogError("Error message: %s", responseBody);
        }
    }*/
    else {
        if (strlen(responseBody) > 0) {
            LogError("Status code: %i Error message: %s", statusCode, responseBody);
        }
    }

}

public int SteamWorks_OnNewRoundSent(Handle request, bool failure, bool requestSuccessful, EHTTPStatusCode statusCode, int serial) {
    if (failure || !requestSuccessful) {
        LogError("API request failed, HTTP status code = %d", statusCode);
        return;
    }

    char responseBody[1024];
    SteamWorks_GetHTTPResponseBodyData(request, responseBody, sizeof(responseBody));

    if (statusCode == k_EHTTPStatusCode200OK) {
        if (serial != 0) {
            int client = GetClientFromSerial(serial);
            PrintToServer("New round successfully sent for client: %i", client);
            PrintToServer("Got response: %s", responseBody);//temporary
            //TODO: parse returned json and update local variables (such as round count)
        }
    } /*else if (statusCode == k_EHTTPStatusCode400BadRequest || statusCode == k_EHTTPStatusCode404NotFound) {
        if (responseBody.length() > 0) {
            LogError("Error message: %s", responseBody);
        }
    }*/
    else {
        if (strlen(responseBody) > 0) {
            LogError("Status code: %i Error message: %s", statusCode, responseBody);
        }
    }

}