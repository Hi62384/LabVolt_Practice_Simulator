#include <avr/io.h>
#include <util/delay.h>
static unsigned char spi(unsigned char x){SPDR=x;while(!(SPSR&(1<<SPIF))){}return SPDR;}
static void cs(unsigned char active){if(active)PORTB&=~(1<<2);else PORTB|=(1<<2);}
static void twi(unsigned char flags){TWCR=(1<<TWINT)|(1<<TWEN)|flags;while(!(TWCR&(1<<TWINT))){} }
static void out(unsigned char x){while(!(UCSR0A&(1<<UDRE0))){} UDR0=x;}
int main(void){
 UBRR0=103;UCSR0C=6;UCSR0B=(1<<TXEN0)|(1<<RXEN0);
#if TEST_KIND==1
 DDRB=(1<<5)|(1<<3)|(1<<2);cs(0);SPCR=(1<<SPE)|(1<<MSTR)|3;
 cs(1);spi(6);cs(0);cs(1);spi(2);spi(0);spi(16);spi(0x5a);cs(0);_delay_ms(6);
 cs(1);spi(3);spi(0);spi(16);unsigned char value=spi(255);cs(0);out(value);
#elif TEST_KIND==2
 TWBR=72;twi(1<<TWSTA);TWDR=0x40;twi(0);out(TWSR&0xf8);
 TWDR=0xa5;twi(0);out(TWSR&0xf8);TWCR=(1<<TWINT)|(1<<TWEN)|(1<<TWSTO);
 _delay_ms(1);twi(1<<TWSTA);TWDR=0x41;twi(0);twi(0);out(TWDR);TWCR=(1<<TWINT)|(1<<TWEN)|(1<<TWSTO);
#elif TEST_KIND==3
 out(0x55);while(!(UCSR0A&(1<<RXC0))){}out(UDR0);
#elif TEST_KIND==4
 out(0x3c);while(!(UCSR0A&(1<<RXC0))){}out(UDR0);
#elif TEST_KIND==5
 while(!(UCSR0A&(1<<RXC0))){}out(UDR0^255);
#elif TEST_KIND==6
 _delay_ms(4);TWBR=72;twi(1<<TWSTA);TWDR=0x41;twi(0);twi(0);out(TWDR);TWCR=(1<<TWINT)|(1<<TWEN)|(1<<TWSTO);
#endif
 for(;;){}
}
