#!/usr/bin/python3
import argparse
import re
import os, libvirt
from typing import Callable, Optional, Any, Dict

"""
https://libvirt.org/formatdomain.html#relationship-between-serial-ports-and-consoles
https://gitlab.com/qemu-project/qemu/-/blob/master/include/hw/virtio/virtio-serial.h?ref_type=heads#L215
https://github.com/qemu/qemu/blob/e22f675bdd3689472032d0de0799519c3e07fd2c/hw/char/virtio-console.c
http://www.linux-kvm.org/page/Virtio-serial_API
"""


def main():
    args = parse_args()

    libvirt.virEventRegisterDefaultImpl()
    libvirt.registerErrorHandler(error_handler, None)

    console = Console(args.uri, args.name)

    # set processing using callbacks linked list
    cb = CallbackList(read_until(find_str), None, expect="Login:")
    #NOTE username+CT, see https://help.mikrotik.com/docs/display/ROS/Command+Line+Interface
    cb = cb.add(send_command("admin+ct"))
    cb = cb.add(read_until(find_str), expect="Password:")
    cb = cb.add(send_command("\n"))
    cb = cb.add(read_until(find_str), expect="Do you want to see the software license",
                search_len=700)
    cb = cb.add(send_command("N"))
    cb = cb.add(read_until(find_str), expect="new password")
    cb = cb.add(send_command("123456\r"))
    cb = cb.add(read_until(find_str), expect="repeat new password")
    cb = cb.add(send_command("123456\r"))
    cb = cb.add(read_until(find_str), expect="MikroTik] >")

    with open('router.sh', 'r') as file:
        commands = file.readlines()
    for command in commands:
        command = command.strip()
        if not command:
            continue
        cb = cb.add(send_command(command))
        cb = cb.add(read_until(find_str), expect="MikroTik] >")

    processor = LibvirtConsoleHandler(console, cb)
    processor.run()


def parse_args():
    parser = argparse.ArgumentParser(description="Connect to MikroTik Cloud Hosted Router via serial console")
    parser.add_argument('--uri', default="qemu:///session", help="QEMU uri")
    parser.add_argument('--name', default="", help="Name of the virtual machine")
    parser.add_argument('--log', default="console.log", help="Log file")

    args, unknown = parser.parse_known_args()
    for arg in unknown:
        if '=' in arg:
            key, value = arg.split('=', 1)
            setattr(args, key.lstrip('-'), value)

    return args


def error_handler(unused, error):
    # The console stream errors on VM shutdown; we don't care
    if (error[0] == libvirt.VIR_ERR_RPC and
            error[1] == libvirt.VIR_FROM_STREAMS):
        return
    os.write(2,error)


class Console(object):
    def __init__(self, uri, name):
        self.uri = uri
        self.name = name
        self.connection = libvirt.open(uri)
        self.domain = self.connection.lookupByName(name)
        self.state = self.domain.state(0)
        self.connection.domainEventRegister(lifecycle_callback, self)
        self.stream = None
        self.run_console = True
        self.remaining_bytes = b''




class CallbackList:
    def __init__(self, cb: Callable[..., Any], next_cb: Optional['CallbackList'] = None, **args):
        self._current: Callable[..., Any] = cb
        self._next: Optional['CallbackList'] = next_cb
        self._args: Dict[str, Any] = args
        self._previous: Optional['CallbackList'] = None

    def add(self, cb: Callable[..., Any], **args) -> 'CallbackList':
        new_node = CallbackList(cb, None, **args)
        return self.append(new_node)

    def append(self, new_node: 'CallbackList') -> 'CallbackList':
        new_node._previous = self
        cursor = self
        while cursor._next:
            cursor = cursor._next  # advance cursor++
        # connect to the last element
        cursor._next = new_node
        return self

    def previous(self) -> tuple[Optional['CallbackList'], Dict[str, Any]]:
        if self._previous:
            return self._previous, self._previous._args
        return None, {}

    def current(self) -> tuple[Callable[..., Any], Dict[str, Any]]:
        return self._current, self._args

    def next(self):
        nxt = self._next
        if nxt is None:
            self._current = None
            return
        self._current = nxt._current
        self._args = nxt._args
        self._next = nxt._next
        nxt._previous = self

    def retry(self):
        pass

    def is_tail(self):
        return self._current is None

    def branch(self, skip_to: 'CallbackList'):
        skip_to._previous = self
        self._current = skip_to._current
        self._args = skip_to._args
        self._next = skip_to._next


MAX_BUFFER_SIZE = 1024 * 1024 * 64


def read_until(condition_fn: Callable[[Any, Any, Any], Any]):
    def _read_until(stream, events, data: ConsoleContext, **args):
        console = data.console
        decoded_buffer = getattr(data, 'decoded_buffer', '')

        while True:
            recv_data = console.stream.recv(1024 * 32)
            if isinstance(recv_data, int) and recv_data <= 0:
                """Console not ready. Continue from __init__ main loop"""
                data.set_return(decoded_buffer=decoded_buffer)
                return None

            decoded_buffer += recv_data.decode('utf-8')
            decoded_buffer = remove_escape(decoded_buffer)
            data.set_return(decoded_buffer=decoded_buffer)

            res = condition_fn(decoded_buffer, data, **args)
            if res:
                os.write(1, (decoded_buffer + '\n').encode("utf-8"))
                setattr(data, 'decoded_buffer', '')
                ret = data.set_return(**res)
                return ret

    return _read_until


def remove_escape(text):
    combined_expect = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])|\x1b\[9999B|\r')
    return combined_expect.sub('', text)


def find_str(text, data, **search_params):
    expect = search_params['expect']
    length = search_params.get('search_len')
    match = re.search(expect, text)
    if match:
        return {'match': match}
    return None


def send_command(cmd):
    def _send(stream, events, context, **args):
        nonlocal cmd
        if not cmd.endswith('\r'):
            cmd += '\r'
        try:
            context.console.stream.send(cmd.encode('utf-8'))
        except libvirt.libvirtError as e:
            # if you debug it can result in broken pipe when send is called
            os.error(e)
            breakpoint()
            return None
        return context

    return _send


def lifecycle_callback(connection, domain, event, detail, console):
    console.state = console.domain.state(0)


class ConsoleContext:
    def __init__(self, console, callbacks: 'CallbackList'):
        self.console = console
        self._callbacks = callbacks

    @property
    def callbacks(self):
        return self._callbacks

    def update_callbacks(self, cb):
        self._callbacks = cb

    def __copy__(self):
        new_instance = self.__class__.__new__(self.__class__)
        new_instance.__dict__.update(self.__dict__)
        return new_instance

    def set_return(self, **args):
        for field, value in args.items():
            setattr(self, field, value)
        return self


class LibvirtConsoleHandler:
    def __init__(self, console: Any, initial_callbacks: CallbackList):
        self._context = ConsoleContext(console, initial_callbacks)
        console.stdin_watch = libvirt.virEventAddHandle(0, libvirt.VIR_EVENT_HANDLE_READABLE, self.stdin_callback, self)

    def stdin_callback(self, watch: int, fd: int, events: int, _self: 'LibvirtConsoleHandler') -> None:
        self = _self  # to ensure to work with appropriate object
        console = self._context.console
        readbuf = os.read(fd, 1024)
        if readbuf.startswith(b""):
            console.run_console = False
            return
        if console.stream:
            console.stream.send(readbuf)

    def main_callback(self, stream: Any, events: int, _self: 'LibvirtConsoleHandler') -> None:
        self = _self
        while True:
            callbacks = self._context.callbacks
            if callbacks.is_tail():
                stream.eventRemoveCallback()
                exit(0)

            current_fn, args = callbacks.current()
            result = current_fn(stream, events, self._context, **args)

            if result is None:
                self._handle_no_result(args)
                return
            else:
                self._context = result
                callbacks.next()

    def _handle_no_result(self, args):
        if 'skip_to' in args:
            skip_to: Optional['CallbackList'] = args['skip_to']
            self._context.callbacks.branch(skip_to)
        else:
            self._context.callbacks.retry()

    def check_console(self) -> bool:
        console = self._context.console
        if (console.state[0] == libvirt.VIR_DOMAIN_RUNNING or
                console.state[0] == libvirt.VIR_DOMAIN_PAUSED):
            if console.stream is None:
                console.stream = console.connection.newStream(libvirt.VIR_STREAM_NONBLOCK)
                console.domain.openConsole(None, console.stream, libvirt.VIR_DOMAIN_CONSOLE_FORCE)
                console.stream.eventAddCallback(libvirt.VIR_STREAM_EVENT_READABLE, self.main_callback, self)
        else:
            if console.stream:
                console.stream.eventRemoveCallback()
                console.stream = None

        return console.run_console

    def run(self) -> None:
        while self.check_console():
            libvirt.virEventRunDefaultImpl()


if __name__ == "__main__":
    main()
