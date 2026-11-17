#define _CRT_SECURE_NO_WARNINGS
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#pragma comment(lib,"Ws2_32.lib")

int wmain(int argc,wchar_t **argv) {
    if(argc<2)return 2;
    if(!wcscmp(argv[1],L"file") && argc==3) {
        HANDLE read=CreateFileW(argv[2],GENERIC_READ,FILE_SHARE_READ,NULL,OPEN_EXISTING,0,NULL);
        HANDLE write=CreateFileW(argv[2],GENERIC_WRITE,FILE_SHARE_READ,NULL,OPEN_EXISTING,0,NULL);
        int denied=(read==INVALID_HANDLE_VALUE && write==INVALID_HANDLE_VALUE);
        if(read!=INVALID_HANDLE_VALUE)CloseHandle(read);
        if(write!=INVALID_HANDLE_VALUE)CloseHandle(write);
        puts(denied?"FILE_DENIED":"FILE_ACCESSIBLE");return denied?0:10;
    }
    if(!wcscmp(argv[1],L"network") && argc==3) {
        WSADATA data;if(WSAStartup(MAKEWORD(2,2),&data))return 11;
        SOCKET s=socket(AF_INET,SOCK_STREAM,IPPROTO_TCP);
        if(s==INVALID_SOCKET)return 12;
        struct sockaddr_in address;ZeroMemory(&address,sizeof(address));address.sin_family=AF_INET;
        address.sin_addr.s_addr=htonl(INADDR_LOOPBACK);address.sin_port=htons((u_short)_wtoi(argv[2]));
        u_long nonblocking=1;ioctlsocket(s,FIONBIO,&nonblocking);
        int result=connect(s,(struct sockaddr*)&address,sizeof(address));
        if(result==SOCKET_ERROR && WSAGetLastError()==WSAEWOULDBLOCK){
            fd_set writable;FD_ZERO(&writable);FD_SET(s,&writable);
            struct timeval limit={1,0};result=select(0,NULL,&writable,NULL,&limit);
            if(result>0){int error=0;int length=sizeof(error);getsockopt(s,SOL_SOCKET,SO_ERROR,(char*)&error,&length);result=error?SOCKET_ERROR:0;}
            else result=SOCKET_ERROR;
        }
        closesocket(s);WSACleanup();puts(result==0?"NETWORK_CONNECTED":"NETWORK_DENIED");
        return result==0?13:0;
    }
    if(!wcscmp(argv[1],L"timeout")){Sleep(15000);return 14;}
    if(!wcscmp(argv[1],L"output")){for(int i=0;i<30000;i++)puts("OUTPUT_LIMIT_PROBE_0123456789");return 0;}
    if(!wcscmp(argv[1],L"memory")) {
        void *p=VirtualAlloc(NULL,600ULL*1024*1024,MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE);
        if(p){volatile char *bytes=(volatile char*)p;for(size_t i=0;i<600ULL*1024*1024;i+=4096)bytes[i]=1;puts("MEMORY_GRANTED");return 15;}
        puts("MEMORY_DENIED");return 0;
    }
    if(!wcscmp(argv[1],L"childwait")){Sleep(15000);return 0;}
    if(!wcscmp(argv[1],L"descendant") && argc==3) {
        STARTUPINFOW start;PROCESS_INFORMATION process;ZeroMemory(&start,sizeof(start));ZeroMemory(&process,sizeof(process));start.cb=sizeof(start);
        wchar_t command[2048];swprintf_s(command,2048,L"\"%ls\" childwait",argv[2]);
        if(!CreateProcessW(argv[2],command,NULL,NULL,FALSE,CREATE_NO_WINDOW,NULL,NULL,&start,&process))return 16;
        printf("CHILD_PID=%lu\n",process.dwProcessId);fflush(stdout);
        CloseHandle(process.hThread);CloseHandle(process.hProcess);return 0;
    }
    return 3;
}
