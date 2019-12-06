package asys.uv;

extern enum abstract UVErrorType(String) to String {
	var E2BIG = 'Argument list too long';
	var EACCES = 'Permission denied';
	var EADDRINUSE = 'Address already in use';
	var EADDRNOTAVAIL = 'Address not available';
	var EAFNOSUPPORT = 'Address family not supported';
	var EAGAIN = 'Resource temporarily unavailable';
	var EAI_ADDRFAMILY = 'Address family not supported';
	var EAI_AGAIN = 'Temporary failure';
	var EAI_BADFLAGS = 'Bad ai_flags value';
	var EAI_BADHINTS = 'Invalid value for hints';
	var EAI_CANCELED = 'Request canceled';
	var EAI_FAIL = 'Permanent failure';
	var EAI_FAMILY = 'Ai_family not supported';
	var EAI_MEMORY = 'Out of memory';
	var EAI_NODATA = 'No address';
	var EAI_NONAME = 'Unknown node or service';
	var EAI_OVERFLOW = 'Argument buffer overflow';
	var EAI_PROTOCOL = 'Resolved protocol is unknown';
	var EAI_SERVICE = 'Service not available for socket type';
	var EAI_SOCKTYPE = 'Socket type not supported';
	var EALREADY = 'Connection already in progress';
	var EBADF = 'Bad file descriptor';
	var EBUSY = 'Resource busy or locked';
	var ECANCELED = 'Operation canceled';
	var ECHARSET = 'Invalid Unicode character';
	var ECONNABORTED = 'Software caused connection abort';
	var ECONNREFUSED = 'Connection refused';
	var ECONNRESET = 'Connection reset by peer';
	var EDESTADDRREQ = 'Destination address required';
	var EEXIST = 'File already exists';
	var EFAULT = 'Bad address in system call argument';
	var EFBIG = 'File too large';
	var EHOSTUNREACH = 'Host is unreachable';
	var EINTR = 'Interrupted system call';
	var EINVAL = 'Invalid argument';
	var EIO = 'I/o error';
	var EISCONN = 'Socket is already connected';
	var EISDIR = 'Illegal operation on a directory';
	var ELOOP = 'Too many symbolic links encountered';
	var EMFILE = 'Too many open files';
	var EMSGSIZE = 'Message too long';
	var ENAMETOOLONG = 'Name too long';
	var ENETDOWN = 'Network is down';
	var ENETUNREACH = 'Network is unreachable';
	var ENFILE = 'File table overflow';
	var ENOBUFS = 'No buffer space available';
	var ENODEV = 'No such device';
	var ENOENT = 'No such file or directory';
	var ENOMEM = 'Not enough memory';
	var ENONET = 'Machine is not on the network';
	var ENOPROTOOPT = 'Protocol not available';
	var ENOSPC = 'No space left on device';
	var ENOSYS = 'Function not implemented';
	var ENOTCONN = 'Socket is not connected';
	var ENOTDIR = 'Not a directory';
	var ENOTEMPTY = 'Directory not empty';
	var ENOTSOCK = 'Socket operation on non-socket';
	var ENOTSUP = 'Operation not supported on socket';
	var EPERM = 'Operation not permitted';
	var EPIPE = 'Broken pipe';
	var EPROTO = 'Protocol error';
	var EPROTONOSUPPORT = 'Protocol not supported';
	var EPROTOTYPE = 'Protocol wrong type for socket';
	var ERANGE = 'Result too large';
	var EROFS = 'Read-only file system';
	var ESHUTDOWN = 'Cannot send after transport endpoint shutdown';
	var ESPIPE = 'Invalid seek';
	var ESRCH = 'No such process';
	var ETIMEDOUT = 'Connection timed out';
	var ETXTBSY = 'Text file is busy';
	var EXDEV = 'Cross-device link not permitted';
	var UNKNOWN = 'Unknown error';
	var EOF = 'End of file';
	var ENXIO = 'No such device or address';
	var EMLINK = 'Too many links';
	var EHOSTDOWN = 'Host is down';
	var EOTHER = 'Unknown error within libuv or libuv glue code';
}