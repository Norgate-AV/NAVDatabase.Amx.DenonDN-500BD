MODULE_NAME='mDenonDN-500BD'	(
                                    dev vdvObject,
                                    dev dvPort
                                )

(***********************************************************)
#DEFINE USING_NAV_MODULE_BASE_CALLBACKS
#DEFINE USING_NAV_MODULE_BASE_PROPERTY_EVENT_CALLBACK
#DEFINE USING_NAV_MODULE_BASE_PASSTHRU_EVENT_CALLBACK
#include 'NAVFoundation.ModuleBase.axi'
#include 'NAVFoundation.SocketUtils.axi'
#include 'NAVFoundation.TimelineUtils.axi'
#include 'NAVFoundation.ErrorLogUtils.axi'

/*
 _   _                       _          ___     __
| \ | | ___  _ __ __ _  __ _| |_ ___   / \ \   / /
|  \| |/ _ \| '__/ _` |/ _` | __/ _ \ / _ \ \ / /
| |\  | (_) | | | (_| | (_| | ||  __// ___ \ V /
|_| \_|\___/|_|  \__, |\__,_|\__\___/_/   \_\_/
                 |___/

MIT License

Copyright (c) 2023 Norgate AV Services Limited

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

(***********************************************************)
(*          DEVICE NUMBER DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_DEVICE

(***********************************************************)
(*               CONSTANT DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_CONSTANT

constant long TL_SOCKET_CHECK = 1
constant long TL_HEARTBEAT = 3

constant long TL_SOCKET_CHECK_INTERVAL[] = { 3000 }
constant long TL_HEARTBEAT_INTERVAL[] = { 20000 }

constant integer IP_PORT = 9030

(***********************************************************)
(*              DATA TYPE DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_TYPE

(***********************************************************)
(*               VARIABLE DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_VARIABLE

volatile _NAVModule module
volatile char trayState

(***********************************************************)
(*               LATCHING DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_LATCHING

(***********************************************************)
(*       MUTUALLY EXCLUSIVE DEFINITIONS GO BELOW           *)
(***********************************************************)
DEFINE_MUTUALLY_EXCLUSIVE

(***********************************************************)
(*        SUBROUTINE/FUNCTION DEFINITIONS GO BELOW         *)
(***********************************************************)
(* EXAMPLE: DEFINE_FUNCTION <RETURN_TYPE> <NAME> (<PARAMETERS>) *)
(* EXAMPLE: DEFINE_CALL '<NAME>' (<PARAMETERS>) *)

define_function SendString(char payload[]) {
    if (dvPort.NUMBER == 0) {
        NAVErrorLog(NAV_LOG_LEVEL_DEBUG,
                NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_STRING_TO,
                                            dvPort,
                                            payload))
    }

    send_string dvPort, "payload"
}


define_function char[NAV_MAX_BUFFER] BuildString(char message[]) {
    return "'@0', message, NAV_CR"
}


define_function MaintainSocketConnection() {
    if (module.Device.SocketConnection.IsConnected) {
        return
    }

    NAVClientSocketOpen(dvPort.PORT,
                        module.Device.SocketConnection.Address,
                        module.Device.SocketConnection.Port,
                        IP_TCP)
}


define_function char[NAV_MAX_CHARS] GetBaudRate(integer port) {
    if (port < 9) {
        return '115200'
    }

    return '9600'
}


#IF_DEFINED USING_NAV_MODULE_BASE_PROPERTY_EVENT_CALLBACK
define_function NAVModulePropertyEventCallback(_NAVModulePropertyEvent event) {
    switch (event.Name) {
        case NAV_MODULE_PROPERTY_EVENT_IP_ADDRESS: {
            module.Device.SocketConnection.Address = NAVTrimString(event.Args[1])
            module.Device.SocketConnection.Port = IP_PORT
            NAVTimelineStart(TL_SOCKET_CHECK,
                            TL_SOCKET_CHECK_INTERVAL,
                            TIMELINE_ABSOLUTE,
                            TIMELINE_REPEAT)
        }
    }
}
#END_IF


#IF_DEFINED USING_NAV_MODULE_BASE_PASSTHRU_EVENT_CALLBACK
define_function NAVModulePassthruEventCallback(_NAVModulePassthruEvent event) {
    if (event.Device != vdvObject) {
        return
    }

    SendString("event.Payload, NAV_CR")
}
#END_IF


define_function Reset() {
    module.Device.SocketConnection.IsConnected = false
    module.Device.IsCommunicating = false
    UpdateFeedback()

    NAVTimelineStop(TL_HEARTBEAT)
}


define_function CommunicationTimeOut(integer timeout) {
    cancel_wait 'TimeOut'

    module.Device.IsCommunicating = true
    UpdateFeedback()

    wait (timeout * 10) 'TimeOut' {
        module.Device.IsCommunicating = false
        UpdateFeedback()
    }
}


define_function UpdateFeedback() {
    [vdvObject, NAV_IP_CONNECTED]	= (module.Device.SocketConnection.IsConnected)
    [vdvObject, DEVICE_COMMUNICATING] = (module.Device.IsCommunicating)
}


(***********************************************************)
(*                STARTUP CODE GOES BELOW                  *)
(***********************************************************)
DEFINE_START {
    NAVModuleInit(module)
}

(***********************************************************)
(*                THE EVENTS GO BELOW                      *)
(***********************************************************)
DEFINE_EVENT

data_event[dvPort] {
    online: {
        if (data.device.number != 0) {
            NAVCommand(data.device, "'SET MODE DATA'")
            NAVCommand(data.device, "'SET BAUD ', GetBaudRate(data.device.port),',N,8,1 485 DISABLE'")
            NAVCommand(data.device, "'B9MOFF'")
            NAVCommand(data.device, "'CHARD-0'")
            NAVCommand(data.device, "'CHARDM-0'")
            NAVCommand(data.device, "'HSOFF'")
        }

        if (data.device.number == 0) {
            module.Device.SocketConnection.IsConnected = true
            UpdateFeedback()
            NAVErrorLog(NAV_LOG_LEVEL_DEBUG, "'mDenonDN-500BD => Socket Online'")
        }

        NAVTimelineStart(TL_HEARTBEAT,
                        TL_HEARTBEAT_INTERVAL,
                        TIMELINE_ABSOLUTE,
                        TIMELINE_REPEAT)
    }
    string: {
        [vdvObject, DATA_INITIALIZED] = true

        CommunicationTimeOut(30)

        if (data.device.number == 0) {
            NAVErrorLog(NAV_LOG_LEVEL_DEBUG,
                        NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_STRING_FROM,
                                                    data.device,
                                                    data.text))
        }
    }
    offline: {
        if (data.device.number == 0) {
            NAVClientSocketClose(data.device.port)
            Reset()

            NAVErrorLog(NAV_LOG_LEVEL_DEBUG, "'mDenonDN-500BD => Socket Offline'")
        }
    }
    onerror: {
        if (data.device.number == 0) {
            Reset()

            NAVErrorLog(NAV_LOG_LEVEL_ERROR,
                        "'mDenonDN-500BD => Socket Error: ', NAVGetSocketError(type_cast(data.number))")
        }
    }
}


channel_event[vdvObject, 0] {
    on: {
        switch (channel.channel) {
            case PLAY: SendString(BuildString('2353'))
            case STOP: SendString(BuildString('2354'))
            case PAUSE: SendString(BuildString('2348'))
            case FFWD: SendString(BuildString('PCSLSFf'))
            case REW: SendString(BuildString('PCSLSRf'))
            case SFWD: SendString(BuildString('2332'))
            case SREV: SendString(BuildString('2333'))
            //case POWER: SendString("'800'")
            case PWR_ON: SendString(BuildString('PW00'))
            case PWR_OFF: SendString(BuildString('PW01'))
            case MENU_UP: SendString(BuildString('PCCUSR3'))
            case MENU_DN: SendString(BuildString('PCCUSR4'))
            case MENU_LT: SendString(BuildString('PCCUSR1'))
            case MENU_RT: SendString(BuildString('PCCUSR2'))
            case MENU_SELECT: SendString(BuildString('PCENTR'))
            case MENU_BACK: SendString(BuildString('PCRTN'))
            case 44: { SendString(BuildString('DVTP')) }	//Top Menu
            case 57: { SendString(BuildString('DVSPTL1')) }	//Sub-title
            case 101: { SendString(BuildString('PCHM')) }	//Home
            case 102: { SendString(BuildString('DVPU')) }	//popup menu
            case DISC_TRAY: {
                trayState = !trayState

                if (trayState) {
                    SendString(BuildString('PCDTRYOP'))
                }
                else {
                    SendString(BuildString('PCDTRYCL'))
                }
            }
        }
    }
}


timeline_event[TL_SOCKET_CHECK] { MaintainSocketConnection() }


timeline_event[TL_HEARTBEAT] {
    SendString(BuildString('?VN'))
}


(***********************************************************)
(*                     END OF PROGRAM                      *)
(*        DO NOT PUT ANY CODE BELOW THIS COMMENT           *)
(***********************************************************)
