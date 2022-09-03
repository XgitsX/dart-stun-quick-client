import '../lib/StunManager.dart';
import 'dart:io';

void main(List<String> arguments) {
  StunManager SM = StunManager();
  SM.debug = false;
  testNat(SM);
}

void testNat(StunManager SM) async{
  int rank = await SM.rankNat();
  print("Your rank NAT: $rank");
  exit(0);
}
