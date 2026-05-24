CC=clang
CFLAGS=-O2 -Wall -Wextra
TARGET=RootHelper

all: $(TARGET)

$(TARGET): root_helper.c
	$(CC) $(CFLAGS) -o $(TARGET) root_helper.c

clean:
	rm -f $(TARGET)
