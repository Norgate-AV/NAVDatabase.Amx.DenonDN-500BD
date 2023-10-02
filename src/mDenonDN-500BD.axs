MODULE_NAME='mDenonDN-500BD'	(
                                    dev vdvObject,
                                    dev dvPort
                                )

(***********************************************************)
#DEFINE USING_NAV_MODULE_BASE_PROPERTY_EVENT_CALLBACK
#DEFINE USING_NAV_MODULE_BASE_PASSTHRU_EVENT_CALLBACK
#include 'NAVFoundation.ModuleBase.axi'
#include 'NAVFoundation.SocketUtils.axi'

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

constant long TL_IP_CHECK = 1
constant long TL_HEARTBEAT = 3

constant integer IP_PORT = NAV_TELNET_PORT

(***********************************************************)
(*              DATA TYPE DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_TYPE

(***********************************************************)
(*               VARIABLE DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_VARIABLE

volatile long ipCheck[] = { 3000 }
volatile long heartbeat[] = { 20000 }

volatile integer trayState

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
    payload = "payload, NAV_CR"
    NAVLog(NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_STRING_TO, dvPort, payload))

    send_string dvPort, "payload"
}


define_function char[NAV_MAX_BUFFER] BuildString(char message[]) {
    return "'@0', message, NAV_CR"
}


define_function MaintainIpConnection() {
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
            module.Device.SocketConnection.Address = event.Args[1]
            module.Device.SocketConnection.Port = IP_PORT
            NAVTimelineStart(TL_IP_CHECK, ipCheck, TIMELINE_ABSOLUTE, TIMELINE_REPEAT)
        }
    }
}
#END_IF


#IF_DEFINED USING_NAV_MODULE_BASE_PASSTHRU_EVENT_CALLBACK
define_function NAVModulePassthruEventCallback(char data[]) {
    SendString(data)
}
#END_IF


define_function Reset() {
    module.Device.SocketConnection.IsConnected = false
    module.Device.IsCommunicating = false

    NAVTimelineStop(TL_HEARTBEAT)
}


define_function CommunicationTimeOut(integer timeout) {
    cancel_wait 'TimeOut'

    module.Device.IsCommunicating = true

    wait (timeout * 10) 'TimeOut' {
        module.Device.IsCommunicating = false
    }
}


(***********************************************************)
(*                STARTUP CODE GOES BELOW                  *)
(***********************************************************)
DEFINE_START {

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
        }

        NAVTimelineStart(TL_HEARTBEAT, heartbeat, TIMELINE_ABSOLUTE, TIMELINE_REPEAT)
    }
    string: {
        [vdvObject, DATA_INITIALIZED] = true

        CommunicationTimeOut(30)

        NAVLog(NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_STRING_FROM, data.device.port, data.text))
    }
    offline: {
        if (data.device.number == 0) {
            NAVClientSocketClose(data.device.port)
            Reset()
        }
    }
    onerror: {
        if (data.device.number == 0) {
            Reset()
        }
    }
}

data_event[vdvObject] {
    command: {
        stack_var _NAVSnapiMessage message

        NAVLog(NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_COMMAND_FROM, data.device, data.text))

        NAVParseSnapiMessage(data.text, message)

        switch (message.Header) {
            default: {

            }
        }
    }
}


channel_event[vdvObject,0] {
    on: {
        switch (channel.channel) {
            case PLAY: SendString("'2353'")
            case STOP: SendString("'2354'")
            case PAUSE: SendString("'2348'")
            case FFWD: SendString("'PCSLSFf'")
            case REW: SendString("'PCSLSRf'")
            case SFWD: SendString("'2332'")
            case SREV: SendString("'2333'")
            //case POWER: SendString("'800'")
            case PWR_ON: SendString("'PW00'")
            case PWR_OFF: SendString("'PW01'")
            case MENU_UP: SendString("'PCCUSR3'")
            case MENU_DN: SendString("'PCCUSR4'")
            case MENU_LT: SendString("'PCCUSR1'")
            case MENU_RT: SendString("'PCCUSR2'")
            case MENU_SELECT: SendString("'PCENTR'")
            case MENU_BACK: SendString("'PCRTN'")
            case 44: { SendString("'DVTP'") }	//Top Menu
            case 57: { SendString("'DVSPTL1'") }	//Sub-title
            case 101: { SendString("'PCHM'") }	//Home
            case 102: { SendString("'DVPU'") }	//popup menu
            case DISC_TRAY: {
                trayState = !trayState

                if (trayState) {
                    SendString("'PCDTRYOP'")
                }
                else {
                    SendString("'PCDTRYCL'")
                }
            }
        }
    }
}


timeline_event[TL_IP_CHECK] { MaintainIPConnection() }


timeline_event[TL_HEARTBEAT] {
    // SendString('')
}


timeline_event[TL_NAV_FEEDBACK] {
    [vdvObject, NAV_IP_CONNECTED]	= (module.Device.SocketConnection.IsConnected)
    [vdvObject, DEVICE_COMMUNICATING] = (module.Device.IsCommunicating)
}


(***********************************************************)
(*                     END OF PROGRAM                      *)
(*        DO NOT PUT ANY CODE BELOW THIS COMMENT           *)
(***********************************************************)

