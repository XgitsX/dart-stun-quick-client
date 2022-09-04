// ignore_for_file: avoid_print

import 'dart:io';
import 'package:dart_stun_quick_client/stun_client.dart';

void main(List<String> arguments) {
  final StunClient sc = StunClient();
  sc.debug = false;
  testNat(sc);
}

Future<void> testNat(StunClient sc) async{
  final int rank = await sc.rankNat();
  print('Your address: ${sc.lastReceived?.extIP}:${sc.lastReceived?.extPort}');
  print('Your rank NAT: $rank');
  exit(0);
}
