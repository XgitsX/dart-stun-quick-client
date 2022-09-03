import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:io';
class StunManager{
  bool debug = false;
  static const Duration timeout = Duration(seconds: 3);
  static const int MappedAddress = 0x01;
  static const int ResponseAddress = 0x02;
  static const int ChangeRequest = 0x03;
  static const int SourceAddress = 0x04;
  static const int ChangedAddress = 0x05;
  Uint8List modeHostNormal = Uint8List(0);
  Uint8List modeHostIpChanged = Uint8List.fromList([00,03,00,04,00,00,00,06]);
  Uint8List modeHostPortChanged = Uint8List.fromList([00,03,00,04,00,00,00,02]);
  static const List<String> stunList = [
    'stun.ekiga.net:3478',
    'stun.sipnet.ru:3478',
    'stun.voipbuster.com:3478',
    'stun.voipstunt.com:3478',
    'stun.1und1.de:3478',
    'stun.12connect.com:3478',
    'stun.gmx.de:3478',
    'stun.sip.us:3478',
    'stun.12voip.com:3478'
  ];

  String currentServer = "stun.ekiga.net";
  int indexList = 0;

  RawDatagramSocket? socket;  
  InternetAddress? ip; int port = 3478;
  Datagram? dg;

  Future<StunRequest?> init() async{
    try {
      _changeServerRandom();
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      print("Open UDP socket - ${socket!.address.address}:${socket!.port}");
      socket!.listen((event) {
          if (event == RawSocketEvent.read) {
            // Receive data
            dg = socket!.receive();
            if(debug && dg != null) print("receive ${dg?.data.length} bytes from ${dg?.address.address}:${dg?.port}");
          }
      });
      int failCount=0;
      StunRequest? stunTest;
      while(ip == null) {
        ip = await _getHostIp();
        if(ip != null){
          stunTest = await _openPort();
          if(stunTest != null){
            break;
          }else {
            ip = null;
          }
        }
        _listServer();
        failCount++;
        if(failCount>=10) throw("Not internet");
      }
      return stunTest;

    }catch(err){
      print(err);
    }
    return null;
  }
  Future<InternetAddress?> _getHostIp() async{
    try {
      return (await InternetAddress.lookup(currentServer).timeout(timeout))[0];
    }catch(_){
    }
    return null;
  }
  void _changeServerRandom(){
    indexList = Random().nextInt(stunList.length);
    String ipAndPort = stunList[indexList];
    currentServer = ipAndPort.split(':')[0];
    port = int.parse(ipAndPort.split(':')[1]);
  }
  void _listServer(){
    indexList++;
    if(indexList>=stunList.length) indexList=0;
    String ipAndPort = stunList[indexList];
    currentServer = ipAndPort.split(':')[0];
    port = int.parse(ipAndPort.split(':')[1]);
  }

  Future<StunRequest?> _openPort() async{
      return await _requestStun(modeHostNormal);
  }

  Future<bool> testFullCone() async{
      return await _requestStun(modeHostIpChanged) == null ? false : true;
  }
  Future<bool> testRestricted() async{
      return await _requestStun(modeHostPortChanged) == null ? false : true;
  }
  Future<StunRequest?> get() async{
    return await _requestStun(modeHostNormal);
  }

  Future<StunRequest?> _requestStun(Uint8List data) async{
    try {
      Uint8List buffer = _createBuffer(data);
      if(debug) print("send ${buffer.length} bytes to ${ip?.address}:$port (${ip?.host})");
      socket!.send(buffer, ip!, port);
      for(int t=0; t<19; t++){
        if(dg!=null){
          return _datagramToStunRequest(dg);
        }
        if(t%10 == 9) {
          if(debug) print("resend ${buffer.length} bytes to ${ip?.address}:$port");
          socket!.send(buffer, ip!, port);
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }catch(err){}
    return null;
  }

  StunRequest? _datagramToStunRequest(Datagram? dg) {
    if (dg == null) return null;
    if(debug) print("handle ${dg.data.length} bytes from ${dg.address.address}:${dg.port}");
    if(dg.data.length < 30 || dg.data.length > 299) return null;
    int i=20;

    ByteData byteData = ByteData.sublistView(dg.data);
    StunRequest result = StunRequest();
    String strIp = "";
    int attrType = 0, attrLen = 0, port = 0;
    for (int i=20; i<dg.data.length-9;) {
      attrType = byteData.getUint16(i);
      attrLen = byteData.getUint16(i+2);
      port = byteData.getUint16(i+6);
      strIp = "${dg.data[i+8]}.${dg.data[i+9]}.${dg.data[i+10]}.${dg.data[i+11]}";
      i+=attrLen+4;
      switch(attrType){
        case MappedAddress:{
          result.extIP = strIp;
          result.extPort = port;
          break;
        }
        case SourceAddress:{
          result.sourceIP = strIp;
          result.sourcePort = port;
          break;
        }
        case ChangedAddress:{
          result.changedIP = strIp;
          result.changedPort = port;
          break;
        }
      } // switch
    } // for
    if(debug) print(result.convertToString());
    this.dg=null;
    return result;
  }

  Uint8List _createBuffer(Uint8List data){
    Uint8List l = Uint8List(20);
    l[0]=0;
    l[1]=1;
    l[2]=0;
    l[3]=data.length;
    for(int i=4; i<20; i++) {
      l[i]=Random().nextInt(255);
    }
    BytesBuilder b = BytesBuilder();
    b.add(l);
    b.add(data);
    return b.toBytes();
  }
  
  void dispose(){
    //socket.dispose();
  }

  Future<int> rankNat() async{
    StunRequest? sr = await init();
    if(sr == null){
		print("ConnectionError");
        return -1;
	  }
    print("Your Address and Port: ${sr.extIP}:${sr.extPort}");
      if(socket?.address.address == sr.extIP){
        print("OpenInternet");
        return 0;
      }

      if(await testFullCone()){
        print("FullCone NAT");
        return 1;
      };

      ip = InternetAddress(sr.changedIP!);
      port = sr.changedPort!;

      StunRequest? sr2 = await get();
      if(sr2 == null){
        print("ChangedAddressError");
        return -1;
      }
      if(sr.extIP != sr2.extIP || sr.extPort != sr2.extPort){
        print("Symmetric NAT");
        return 4;
      }

      if(await testRestricted()){
        print("Restricted Address NAT");
        return 2;
      } //else{
        print("Restricted Address and Port NAT");
        return 3;
      //};
  }
}

class StunRequest{
  String? extIP; int? extPort;
  String? sourceIP; int? sourcePort;
  String? changedIP; int? changedPort;
  String convertToString(){
    return " \n Your IP: $extIP:$extPort \n Source IP: $sourceIP:$sourcePort \n ChangedIP: $changedIP:$changedPort";
  }
}