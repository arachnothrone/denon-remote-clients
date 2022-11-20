//
//  Comm.swift
//  DenonRemote
//
//  Created by arachnothrone on 2022-11-19.
//

import Foundation
import Darwin
import Darwin.sys

class AsyncOperation {

    private let semaphore: DispatchSemaphore
    private let dispatchQueue: DispatchQueue
    typealias CompleteClosure = ()->()

    init(numberOfSimultaneousActions: Int, dispatchQueueLabel: String) {
        semaphore = DispatchSemaphore(value: numberOfSimultaneousActions)
        dispatchQueue = DispatchQueue(label: dispatchQueueLabel)
    }

    func run(closure: @escaping (@escaping CompleteClosure)->()) {
        dispatchQueue.async {
            self.semaphore.wait()
            closure {
                self.semaphore.signal()
            }
        }
    }
}

let asyncOperation = AsyncOperation(numberOfSimultaneousActions: 1, dispatchQueueLabel: "AnyString")

struct MEM_STATE_T {
    var power:      String = "0"
    var volume:     String = "---"
    var mute:       String = "0"
    var stereoMode: String = "0"
    var input:      String = "0"
    var dimmer:     String = "0"
}

func htons(value: CUnsignedShort) -> CUnsignedShort {
    return (value << 8) + (value >> 8);
}

func udpSendString(textToSend: String, address: String, port: CUnsignedShort, rxTimeoutSec: Int) -> String {
    var adr = in_addr()
    inet_pton(AF_INET, address, &adr)

    let fd = socket(AF_INET, SOCK_DGRAM, 0) // UDP
    let addr = sockaddr_in(
        sin_len:    __uint8_t(MemoryLayout<sockaddr_in>.size),
        sin_family: sa_family_t(AF_INET),
        sin_port:   htons(value: port),
        sin_addr:   adr, //address, =>>> addr=6502a8c0  65 02  a8  c0 <- eto 192.168.2.101
                         //                            101  2 168 192
        sin_zero:   (0, 0, 0, 0, 0, 0, 0, 0)
    )

    let sent = textToSend.withCString {cstr -> Int in
        var localCopy = addr
        let sent = withUnsafePointer(to: &localCopy) { pointer -> Int in
            let memory = UnsafeRawPointer(pointer).bindMemory(to: sockaddr.self, capacity: 1)
            let sent = sendto(fd, cstr, strlen(cstr), 0, memory, socklen_t(addr.sin_len))
            return sent
        }

        return sent
    }
    
    print("Sent \(sent) bytes")
    
    let rxBufSize = 15
    var rxBuffer: Array<UInt8> = Array(repeating: 0, count: rxBufSize)
    let numFDs: Int32 = 32
    var rfds: fd_set = .init()
    var wfds: fd_set = .init()
    var efds: fd_set = .init()
    var tv: timeval = .init(tv_sec: rxTimeoutSec, tv_usec: 0)
    var timeStamp0: timespec = .init()
    var timeStamp1: timespec = .init()
    
    var receivedString = ""
    
    //__DARWIN_FD_ZERO(&rfds)
    print("socket: \(fd), rfds(before): \(rfds.fds_bits)")
    __darwin_fd_set(fd, &rfds)
    print("socket: \(fd), rfds(after) : \(rfds.fds_bits)")
    //rfds = .init()
    //memset(&rfds, 0, sizeof(rfds)) // FD_SETSIZE
    
    //let retVal = poll()
    //let retVal = select(numFDs, &rfds, NSNull, NSNull, &tv)
    clock_gettime(CLOCK_MONOTONIC, &timeStamp0)
    let retVal = select(numFDs, &rfds, &wfds, &efds, &tv)
    clock_gettime(CLOCK_MONOTONIC, &timeStamp1)
    print("retVal=\(retVal), in \(timeStamp1.tv_sec - timeStamp0.tv_sec)s \(timeStamp1.tv_nsec - timeStamp0.tv_nsec)ns")
    var volumeString = ""

    if retVal == 1 {
        let rxDataLen = recv(fd, &rxBuffer, rxBufSize, 0)
        print("Received data (\(rxDataLen) bytes): \(rxBuffer), \(tv.tv_sec)s \(tv.tv_usec)us")
        for i in [2, 3, 4] {
            let c = UnicodeScalar(rxBuffer[i])
            volumeString = volumeString + String(c)
        }
        
        for i in 0...14 {
            let c = UnicodeScalar(rxBuffer[i])
            receivedString += String(c)
        }
        print("decoded rx string: \(receivedString)")
    } else if retVal == 0 {
        print("Error: select() timeout")
    } else {
        print("Error: select() returned: \(retVal)")
    }
    
    print("Vol: \(volumeString)")

    close(fd)

    return receivedString
}

func sendCommand(cmd: String, rxTO: Int) -> MEM_STATE_T {
    let resultString = udpSendString(textToSend: cmd, address: "192.168.2.101", port: 19001, rxTimeoutSec: rxTO)
    print("sendCommand: cmd=\(cmd), rxTO=\(rxTO), resultString=\(resultString)")
    return deserializeDenonState(ds_string: resultString)
}

func sendCommandW(cmd: String, rxTO: Int) -> String {
    return udpSendString(textToSend: cmd, address: "192.168.2.101", port: 19001, rxTimeoutSec: rxTO)
}

func deserializeDenonState(ds_string: String) -> MEM_STATE_T {
    var denonState: MEM_STATE_T = MEM_STATE_T()
    denonState.power = stringSlicer(inputStr: ds_string, startIdx: 0, sliceLen: 1)
    denonState.volume = stringSlicer(inputStr: ds_string, startIdx: 2, sliceLen: 3)
    denonState.mute = stringSlicer(inputStr: ds_string, startIdx: 6, sliceLen: 1)
    denonState.stereoMode = stringSlicer(inputStr: ds_string, startIdx: 8, sliceLen: 1)
    denonState.input = stringSlicer(inputStr: ds_string, startIdx: 10, sliceLen: 1)
    denonState.dimmer = stringSlicer(inputStr: ds_string, startIdx: 12, sliceLen: 1)
    print("\(getTimeStamp()) power: \(denonState.power), volume: \(denonState.volume), mute: \(denonState.mute), stereoMode: \(denonState.stereoMode), input: \(denonState.input), dimmer: \(denonState.dimmer)")
    return denonState
}

// to convert String -> Bytes use: "string".bytes
extension StringProtocol {
    var data: Data { .init(utf8) }
    var bytes: [UInt8] { .init(utf8) }
}

func stringSlicer(inputStr: String, startIdx: Int, sliceLen: Int) -> String {
    var res = "0"
    
    if inputStr != "" {
        res = String(inputStr[inputStr.index(inputStr.startIndex, offsetBy: startIdx)..<inputStr.index(inputStr.startIndex, offsetBy: startIdx + sliceLen)])
    }
    
    return res
}

func getTimeStamp() -> String {
    let date = Date()
    let calendar = Calendar.current
    let hour = calendar.component(.hour, from: date)
    let minutes = calendar.component(.minute, from: date)
    let seconds = calendar.component(.second, from: date)
    let ms = Int(calendar.component(.nanosecond, from: date) / 1000000)
    return String(format: "%02d:%02d:%02d.%03d", hour, minutes, seconds, ms)
}
