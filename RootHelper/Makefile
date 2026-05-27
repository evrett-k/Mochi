CC=clang
CFLAGS=-O2 -Wall -Wextra
TARGET=RootHelper

all: $(TARGET)

$(TARGET): main.c
	$(CC) $(CFLAGS) -o $(TARGET) main.c

clean:
	rm -f $(TARGET)
