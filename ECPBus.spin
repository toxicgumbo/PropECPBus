{{ Ademco Vista ECP Bus Protocol Decoder
by Joe Lucia 8/2012

To READ the DATA OUT from a Vista ECP Keypad Bus:  (the Slave input line)
Connect Vista Data Out wire to the LED side of an Opto-Isolator with an inline 2.7k resistor.
Connect the Output of the Opto Isolator (colletor) to a Propeller Input with a 10k Pullup. Connect the Emitter side to Gnd.

To WRITE to the DATA IN of a Vista ECP Keypad Bus:  (the Slave output line)
Connect the Output pin of Propeller directly to LED of Opto-Isolator + GND.
Connect VISTA Data In Terminal to the Emitter of an Opto Isolator with a 10k Pull Down.  Connect the Collector to +10v.

}}
con
  maxZones = 200

var
  byte  rxbyte
  long  sin, sout
  byte  buf[100]
  long  bufstart, bufend
  byte  sendBuf[100]
  long  sendBufStart, sendBufEnd 
  long  stk[100]
  long  bittime
  long  keytrigger
  
  byte  tmpPacket[100] ' retrieves current packet into here
  byte  lastPacket[100] ' moves tmpPacket here upon completion 
  byte  lastPacketLen ' length of current lastPacket

  byte  zFault[maxZones+1]
  long  zFaultTime[maxZones+1]
  byte  lcdDisplay[33]
  long  lastPacketNum
  byte  lastStatusByte
  byte  MYADDRESS

PUB StartMaster(rpin,tpin)
  sin := rpin
  sout := tpin
  cognew(MainMaster, @stk)

PUB StartSlave(rpin,tpin,address)
  sin := rpin 
  sout := tpin
  MYADDRESS := address
  cognew(MainSlave, @stk)

PUB rxCheck                     '' return next byte in buffer, -1 if nothing available
  if bufstart==bufend
    return -1
  result := buf[bufstart++]
  if bufstart>99
    bufstart:=0

PUB rxFlush
  bufstart:=bufend:=0
  bytefill(@lastPacket, 0, 100)
  lastPacketLen:=0

PUB rxBufLen                    '' return number of bytes in the buffer
  if bufstart==bufend
    return 0
  if (bufend>bufstart)
    return (bufend-bufstart)
  else
    return (bufend+100) - bufstart

PUB getLastPacketType
  return lastPacket[0]
    
PUB getLastPacket(bufptr)
  bytemove(bufptr, @lastPacket, 100)
  return lastPacketLen

PUB getZoneFaults
  return @zFault

PUB txbufAsMaster(bufptr, buflen) | x,t,i,bnum
  '' transmite a Sync Byte, then bufptr bytes on data out line from panel to a device on the bus when in Master (Alarm Panel) mode
  if sout<0
    return -1

  outa[sout]~~
  waitcnt(cnt+bittime)
  outa[sout]~

var
  byte pktid
  long sendReady
  
PRI addSendBuf(ch)
  sendBuf[sendBufEnd++]:=ch
  if sendBufEnd>99
    sendBufEnd:=0

PRI getSendBuf
  if sendbufstart==sendbufend
    return -1
  result := sendBuf[sendBufStart++]
  if sendBufStart>99
    sendBufStart:=0

PUB tx(ch) | x
  '' transmits byte on the Data-In line on the alarm panel (like a keypad talking to alarm panel) when in Slave (Keypad) Mode
  {
    Key Press = 00..09,0A,0B                                                                                                                                                                               
    Hold Key = 10..19,1A,1B
    Special Keys = 1C,1D,1E,1F
  }
  if pktid==0
    pktid:=1
  sendReady~
  addsendbuf(4) ' send 4 bytes
  addsendbuf(pktid<<4)
  addsendbuf(2)
  addsendbuf(ch)
  addsendbuf(0-(pktid<<4)-2-ch)
  pktid+=4
  sendReady~~

PRI doTxPulse
  outa[sout]~~
  waitcnt(cnt+bittime) 
  outa[sout]~

PRI waitPulse
  waitcnt(cnt+bittime)

PRI MainMaster
  '' listen to keypads and devices on ECP Bus Data In
  '' Transmit display messages to keypads
  '' Transmit sync pulses to allow devices to talk
  '' Respond to pulses from keypad after 13ms pulse followed by three 2ms-off, 1-mson pulses  
    
PRI MainSlave | x,i, h, t, dif
  '' listen to Alarm Panel on ECP Bus Data Out
  '' "be like a keypad"
  bittime := clkfreq/4800
  dira[sin]~    ' make rx pin an input
  dira[sout]~~ ' output
  outa[sout]~
  sendReady~~
  '' STT,B0,B1,B2,B3,B4,B5,B6,B7,P,STP,STP
  repeat
    ' wait for pulse
    RefreshZoneTimers
    waitpeq(|<sin,|<sin,0)
    t := cnt
    waitpne(|<sin,|<sin,0)
    dif := cnt-t
    if (dif > (clkfreq/1000*3)) and (dif < (clkfreq/1000*6)) ' 4ms Sync Pulse for Receiving Data
      GetECPBytes    ' get packet from master
    elseif (dif > (clkfreq/1000*12)) and (dif < (clkfreq/1000*15)) ' 13ms Sync Pulse for Slave to Transmit      
      ' send bytes in sendBuf
      if (sendBufStart<>sendBufEnd) and (sendReady)
        SendKeypadAddress ' request to send our data
           
PRI RefreshZoneTimers | x
  ' reset status on faulted zones if we don't "see" a fault after a few seconds
  repeat x from 0 to maxZones-1
    if zFault[x]>0
      if (cnt-zFaultTime[x] > (clkfreq*6))
        zFault[x]:=0

PRI SendKeypadAddress
  ' send keypad address MYADDRESS
  
  ' first pulse, 0..7
  doTxPulse
  'doTxPulse ' 0
  waitpeq(|<sin, |<sin, 0)
  waitpne(|<sin, |<sin, 0)
   
  ' second puls, 8..15
  doTxPulse
  'doTxPulse ' 8
  waitpeq(|<sin, |<sin, 0)
  waitpne(|<sin, |<sin, 0)
   
  ' third pulse, 16..23
  doTxPulse
  if MYADDRESS==16
    doTxPulse ' 16 = keypad address
  else
    waitPulse
  if MYADDRESS==17
    doTxPulse ' 17
  else
    waitPulse
  if MYADDRESS==18
    doTxPulse ' 18

  'waitpeq(|<sin, |<sin, 0)
  'waitpne(|<sin, |<sin, 0)
   
  ' fourth pulse, 24..30
  'doTxPulse
  'doTxPulse ' 24 = keypad address

  '' You should expect an F6 response followed by MYADDRESS, at which point it is safe to SEND

var
  byte tbyte

PRI SendKeypadBuffer | x,i,start,t,bt,parity,siz
  start:=1
  bt := bittime ' adjust bittime to compensate for delays in bitshifting
  siz := getSendBuf
  repeat siz
    tbyte:=getSendBuf
    if tbyte<0
      quit
    
    t := cnt
    outa[sout]:=1 ' start bit
    waitcnt(t+=bt)
    i:=0
    parity~
    repeat 8           
      outa[sout] := ((tByte>>i++ & 1)<>1)
      if outa[sout]
        !parity
      waitcnt(t+=bt)

    if parity
      outa[sout]:=0 ' parity bit
    else
      outa[sout]:=1 ' parity bit
    waitcnt(t+=bt)
    
    outa[sout]~ ' stop bits
    waitcnt(t+=bt)
    waitcnt(t+=bt)

  ' TODO: wait for ACK immediately after last byte sent, repeat if no ACK received.
  
PRI GetECPBytes | t, i, bnum, ptype '' Receive and Process a packet From the Alarm Panel
  t := cnt - (bittime/2)                              ' start at now + 1/2 bit
  bnum:=0
  ptype:=0
  bytefill(@tmpPacket, 0, 100)
  repeat
    rxbyte:=i:=0

    waitcnt(t += bittime)                             ' wait for middle of start bit
    if ina[sin]  ' check start bit
      quit
      
    repeat 8         ' receive next 8 bits of byte
      waitcnt(t += bitTime)                             ' wait for middle of bit
      rxbyte := rxbyte | (ina[sin]<<(i++))
     
    waitcnt(t += bitTime)                                ' parity bit
    
    waitcnt(t += bitTime)                                ' allow for stop bit
    if not ina[sin]                                      ' verify stop bit
      quit 
    waitcnt(t += bitTime)                                ' allow for stop bit
    if not ina[sin]                                      ' verify stop bit
      quit 

    if bnum==0
      ptype:=rxbyte

    if bnum==1 and ptype==$F6
      '' TRIGGER OUTPUT for SAMPLING keypad bytes
      keyTrigger~~
      ' if we have keyboard output then we should send it NOW
      if rxbyte==MYADDRESS and (sendbufstart<>sendbufend)
        SendKeypadBuffer
        quit

    keyTrigger~                                                                                                                  
       
    ' add to buffer
    tmpPacket[bnum]:=rxbyte
    bnum++ 
    buf[bufend++]:=rxbyte
    if bufend>99
      bufend:=0

  ' save Packet
  bytemove(@lastPacket, @tmpPacket, 100)
  lastPacketLen:=bnum

  lastPacketNum++

  '' Process Packet

  '  .. update Panel Status

  '  F7 = Zone Status Change
  if tmpPacket[0] == $F7
    if tmpPacket[1]==0 and tmpPacket[7]==0
      zFault[tmpPacket[5]] := 1
      zFaultTime[tmpPacket[5]] := cnt
    repeat i from 0 to 31
      tmpPacket[i+12]:=tmpPacket[i+12] & $7F
    bytemove(@lcdDisplay, @tmpPacket[12], 32)
    lastStatusByte := tmpPacket[7]
    
PUB isKeyTrigger
  return keyTrigger

PUB getlcdDisplay
  return @lcdDisplay

PUB getlastPacketNum
  return lastPacketNum

PUB getLastStatusByte
  return lastStatusByte 
  

DAT
{{
Display String is starting at byte 12 on F7 packet asd is 32 bytes long.


F2:12:06:00:00:00:00:62:6C:02:45:6C:F5:EC:01:01:01:00:00:91:
F2:16:06:00:00:00:00:63:63:02:45:43:F5:31:FB:45:6C:F5:EC:01:02:01:06:E5: (alarm)
F7:****DISARMED****Hit * for faults
F2:12:06:00:00:00:00:64:6C:02:45:6C:F5:EC:01:01:01:00:00:8F: (restore)
F7:****DISARMED****  Ready to Arm
F2:16:06:00:00:00:00:65:63:02:45:43:F5:31:FB:45:6C:F5:EC:01:01:01:01:E9:
F2:12:06:00:00:00:00:66:6C:02:45:6C:F5:EC:01:01:01:00:00:8D:
F2:16:06:00:00:00:00:67:63:02:45:43:F5:31:FB:45:6C:F5:EC:01:02:01:06:E1:
F7:****DISARMED****Hit * for faults
F2:12:06:00:00:00:00:60:6C:02:45:6C:F5:EC:01:01:01:00:00:93:
F2:16:06:00:00:00:00:61:63:02:45:43:F5:31:FB:45:6C:F5:EC:01:01:01:01:ED:
F7:****DISARMED****  Ready to Arm

'' Zone 8 Short Open Short Open
(short)
F2:12:06:00:00:00:00:62:6C:02:45:6C:F5:EC:01:01:01:00:00:91:
F2:16:06:00:00:00:00:63:63:02:45:43:F5:31:FB:45:6C:F5:EC:01:02:01:06:E5:
(open)
F2:12:06:00:00:00:00:64:6C:02:45:6C:F5:EC:01:01:01:00:00:8F:
F2:16:06:00:00:00:00:65:63:02:45:43:F5:31:FB:45:6C:F5:EC:01:01:01:01:E9:
(short)
F2:12:06:00:00:00:00:66:6C:02:45:6C:F5:EC:01:01:01:00:00:8D:
F2:16:06:00:00:00:00:67:63:02:45:43:F5:31:FB:45:6C:F5:EC:01:02:01:06:E1:
(open)
F2:12:06:00:00:00:00:60:6C:02:45:6C:F5:EC:01:01:01:00:00:93:
F2:16:06:00:00:00:00:61:63:02:45:43:F5:31:FB:45:6C:F5:EC:01:01:01:01:ED:

(zone 1 short)
F2:12:06:00:00:00:00:62:6C:02:45:6C:
F5:EC:01:01:01:00:00:91:

(zone 1 open)
F2:16:06:00:00:00:00:63:63:02:45:43:
F5:31:FB:45:6C:
F5:EC:01:01:01:07:E5:

(zone 1 short)
F2:12:06:00:00:00:00:64:6C:02:45:6C:
F5:EC:01:01:01:00:00:8F:

(zone 1 open)
F2:16:06:00:00:00:00:65:63:02:45:43:
F5:31:FB:45:6C:
F5:EC:01:01:01:07:E3:

}}
  