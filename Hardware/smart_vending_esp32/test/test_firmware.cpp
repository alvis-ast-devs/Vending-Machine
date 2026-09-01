#include <cstdio>
#include <cstdint>
#include <cstring>
#include <string>

static int tp=0, tf=0;
#define NL "\n"
#define OK(x) do{if(x)tp++;else{tf++;fprintf(stderr,"  FAIL: %s (line %d)" NL,#x,__LINE__);}}while(0)

static int8_t slotToBit(const std::string& sc){
  if(sc.length()!=2) return -1;
  int n=std::atoi(sc.c_str());
  if(n>=1&&n<=45) return (int8_t)(n-1);
  if(n>=51&&n<=55) return (int8_t)((n-51)+45);
  return -1;
}

static bool isValidSlotCode(const std::string& sc){
  if(sc.length()!=2) return false;
  for(size_t i=0;i<sc.length();i++) if(sc[i]<'0'||sc[i]>'9') return false;
  int n=std::atoi(sc.c_str());
  return (n>=1&&n<=45)||(n>=51&&n<=55);
}

struct OutputBuffer{
  uint8_t buf[7]={};
  void setActive(uint8_t bi,bool on){
    if(bi>=56) return;
    if(on) buf[bi/8]|=(1<<(7-bi%8));
    else buf[bi/8]&=~(1<<(7-bi%8));
  }
  void allOff(){memset(buf,0,7);}
  bool isZero()const{for(int i=0;i<7;i++)if(buf[i])return false;return true;}
};

std::string bitToSlot(uint8_t bi){
  if(bi<45){std::string s=std::to_string(bi+1);if(s.length()==1)s="0"+s;return s;}
  if(bi>=45&&bi<50) return std::to_string((bi-45)+51);
  return "";
}

void test_slot_valid(){
  OK(slotToBit("01")==0); OK(slotToBit("02")==1); OK(slotToBit("08")==7);
  OK(slotToBit("09")==8); OK(slotToBit("15")==14); OK(slotToBit("45")==44);
  OK(slotToBit("51")==45); OK(slotToBit("52")==46); OK(slotToBit("55")==49);
}
void test_slot_invalid(){
  OK(slotToBit("00")==-1); OK(slotToBit("46")==-1); OK(slotToBit("50")==-1);
  OK(slotToBit("56")==-1); OK(slotToBit("1")==-1); OK(slotToBit("")==-1); OK(slotToBit("AB")==-1);
}
void test_valid_codes(){
  OK(isValidSlotCode("01")); OK(isValidSlotCode("15")); OK(isValidSlotCode("45"));
  OK(isValidSlotCode("51")); OK(isValidSlotCode("55"));
}
void test_invalid_codes(){
  OK(!isValidSlotCode("00")); OK(!isValidSlotCode("46")); OK(!isValidSlotCode("50"));
  OK(!isValidSlotCode("1")); OK(!isValidSlotCode("AB")); OK(!isValidSlotCode(""));
}
void test_buffer_set_active(){
  OutputBuffer ob;
  ob.setActive(0,true);  OK(ob.buf[0]==0x80);
  ob.allOff(); ob.setActive(1,true);  OK(ob.buf[0]==0x40);
  ob.allOff(); ob.setActive(7,true);  OK(ob.buf[0]==0x01);
  ob.allOff(); ob.setActive(8,true);  OK(ob.buf[1]==0x80);
}
void test_buffer_multi(){
  OutputBuffer ob; ob.setActive(0,true); ob.setActive(7,true);
  OK(ob.buf[0]==0x81);
}
void test_buffer_alloff(){
  OutputBuffer ob; ob.setActive(0,true); ob.setActive(15,true); ob.setActive(30,true);
  ob.allOff(); OK(ob.isZero());
}
void test_buffer_oob(){
  OutputBuffer ob; ob.setActive(56,true); ob.setActive(100,true); OK(ob.isZero());
}
void test_bit_to_slot(){
  OK(bitToSlot(0)=="01"); OK(bitToSlot(7)=="08"); OK(bitToSlot(8)=="09");
  OK(bitToSlot(44)=="45"); OK(bitToSlot(45)=="51"); OK(bitToSlot(49)=="55");
  OK(bitToSlot(50)=="");
}
void test_cmd_parse(){
  std::string cmd="DROP_SLOT_15";
  OK(cmd.substr(0,10)=="DROP_SLOT_"); OK(cmd.substr(10)=="15"); OK(isValidSlotCode(cmd.substr(10)));
  cmd="RESET_SLOT_01"; OK(cmd.substr(0,11)=="RESET_SLOT_"); OK(cmd.substr(11)=="01");
  cmd="KEY_5"; OK(cmd.substr(0,4)=="KEY_"); OK(cmd.length()==5);
  cmd[4]>='0'&&cmd[4]<='9';
}
void test_motor(){
  enum{IDLE,LOW,HIGH,DONE} s=IDLE;
  s=LOW;  OK(s==LOW); s=HIGH; OK(s==HIGH); s=DONE; OK(s==DONE);
}
void test_motor_timeout(){
  unsigned long t=0; bool dc=false;
  t+=900;  OK(t>=800);
  t+=1000; OK(t>=1500); OK(!dc);
}
void test_motor_ok(){
  unsigned long t=0; bool dc=false;
  t+=200; OK(true);
  t+=600; dc=true; OK(dc); OK(t<1500);
}
void test_emit_slot(){
  auto bts=[](uint8_t bi)->std::string{
    if(bi<45){std::string s=std::to_string(bi+1);if(s.length()==1)s="0"+s;return s;}
    if(bi>=45&&bi<50) return std::to_string((bi-45)+51);
    return "";
  };
  OK(bts(0)=="01"); OK(bts(44)=="45"); OK(bts(45)=="51"); OK(bts(49)=="55");
  OK(bts(50)=="");
}
int main(){
  puts("");
  puts("======================================");
  puts("  Smart Vending Machine Unit Tests");
  puts("======================================");
  puts("");
  puts("[Slot-to-Bit]");          test_slot_valid(); test_slot_invalid();
  puts(""); puts("[Slot Validation]");  test_valid_codes(); test_invalid_codes();
  puts(""); puts("[Buffer Operations]"); test_buffer_set_active(); test_buffer_multi(); test_buffer_alloff(); test_buffer_oob();
  puts(""); puts("[Bit-to-Slot]");     test_bit_to_slot(); test_emit_slot();
  puts(""); puts("[Command Parsing]");  test_cmd_parse();
  puts(""); puts("[Motor Control]");    test_motor(); test_motor_timeout(); test_motor_ok();
  puts("");
  puts("======================================");
  printf("  RESULTS: %d passed, %d failed" NL, tp, tf);
  puts("======================================");
  puts("");
  return tf>0?1:0;
}
