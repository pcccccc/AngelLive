function sendWup(t, e, i) {
    var r = new Taf.Wup;
    r.setServant(t),
    r.setFunc(e),
    r.writeStruct("tReq", i);
    var n = new HUYA.WebSocketCommand;
    n.iCmdType = HUYA.EWebSocketCommandType.EWSCmd_WupReq,
    n.vData = r.encode();
    var o = new Taf.JceOutputStream;
    n.writeTo(o);
    return o.getBuffer();
};

function sendRegister(t) {
    var e = new Taf.JceOutputStream;
    t.writeTo(e);
    var i = new HUYA.WebSocketCommand;
    i.iCmdType = HUYA.EWebSocketCommandType.EWSCmd_RegisterReq;
    i.vData = e.getBinBuffer();
    e = new Taf.JceOutputStream;
    i.writeTo(e);
    return e.getBuffer();
};

function test(t) {
    var arrayBuffer = new Uint8Array(t).buffer;
    console.log(arrayBuffer);
    var e = new Taf.JceInputStream(arrayBuffer);
    var i = new HUYA.WebSocketCommand;
    switch (i.readFrom(e),
    i.iCmdType) {
    case HUYA.EWebSocketCommandType.EWSCmd_RegisterRsp:
    return "HUYA.EWebSocketCommandType.EWSCmd_RegisterRsp"
    case HUYA.EWebSocketCommandType.EWSCmdS2C_MsgPushReq:
        e = new Taf.JceInputStream(i.vData.buffer);
        var a = new HUYA.WSPushMessage;
        a.readFrom(e);
        e = new Taf.JceInputStream(a.sMsg.buffer);
        var h = TafMx.UriMapping[a.iUri];
        h && (h = new h);
        h.readFrom(e);
        return JSON.stringify(h)
    default:
    return "HUYA.EWebSocketCommandType.Default"
    }
};


var Taf = Taf || {};
Taf.INT8 = function() {
    this._clone = function() {
        return 0
    }
    ,
    this._write = function(t, e, i) {
        return t.writeInt8(e, i)
    }
    ,
    this._read = function(t, e, i) {
        return t.readInt8(e, !0, i)
    }
    ,
    this._className = function() {
        return Taf.CHAR
    }
}
,
Taf.INT16 = function() {
    this._clone = function() {
        return 0
    }
    ,
    this._write = function(t, e, i) {
        return t.writeInt16(e, i)
    }
    ,
    this._read = function(t, e, i) {
        return t.readInt16(e, !0, i)
    }
    ,
    this._className = function() {
        return Taf.SHORT
    }
}
,
Taf.INT32 = function() {
    this._clone = function() {
        return 0
    }
    ,
    this._write = function(t, e, i) {
        return t.writeInt32(e, i)
    }
    ,
    this._read = function(t, e, i) {
        return t.readInt32(e, !0, i)
    }
    ,
    this._className = function() {
        return Taf.INT32
    }
}
,
Taf.INT64 = function() {
    this._clone = function() {
        return 0
    }
    ,
    this._write = function(t, e, i) {
        return t.writeInt64(e, i)
    }
    ,
    this._read = function(t, e, i) {
        return t.readInt64(e, !0, i)
    }
    ,
    this._className = function() {
        return Taf.INT64
    }
}
,
Taf.UINT8 = function() {
    this._clone = function() {
        return 0
    }
    ,
    this._write = function(t, e, i) {
        return t.writeInt16(e, i)
    }
    ,
    this._read = function(t, e, i) {
        return t.readInt16(e, !0, i)
    }
    ,
    this._className = function() {
        return Taf.SHORT
    }
}
,
Taf.UInt16 = function() {
    this._clone = function() {
        return 0
    }
    ,
    this._write = function(t, e, i) {
        return t.writeInt32(e, i)
    }
    ,
    this._read = function(t, e, i) {
        return t.readInt32(e, !0, i)
    }
    ,
    this._className = function() {
        return Taf.INT32
    }
}
,
Taf.UInt32 = function() {
    this._clone = function() {
        return 0
    }
    ,
    this._write = function(t, e, i) {
        return t.writeInt64(e, i)
    }
    ,
    this._read = function(t, e, i) {
        return t.readInt64(e, !0, i)
    }
    ,
    this._className = function() {
        return Taf.INT64
    }
}
,
Taf.Float = function() {
    this._clone = function() {
        return 0
    }
    ,
    this._write = function(t, e, i) {
        return t.writeFloat(e, i)
    }
    ,
    this._read = function(t, e, i) {
        return t.readFloat(e, !0, i)
    }
    ,
    this._className = function() {
        return Taf.FLOAT
    }
}
,
Taf.Double = function() {
    this._clone = function() {
        return 0
    }
    ,
    this._write = function(t, e, i) {
        return t.writeDouble(e, i)
    }
    ,
    this._read = function(t, e, i) {
        return t.readDouble(e, !0, i)
    }
    ,
    this._className = function() {
        return Taf.DOUBLE
    }
}
,
Taf.STRING = function() {
    this._clone = function() {
        return 0
    }
    ,
    this._write = function(t, e, i) {
        return t.writeString(e, i)
    }
    ,
    this._read = function(t, e, i) {
        return t.readString(e, !0, i)
    }
    ,
    this._className = function() {
        return Taf.STRING
    }
}
,
Taf.BOOLEAN = function() {
    this._clone = function() {
        return !1
    }
    ,
    this._write = function(t, e, i) {
        return t.writeBoolean(e, i)
    }
    ,
    this._read = function(t, e, i) {
        return t.readBoolean(e, !0, i)
    }
    ,
    this._className = function() {
        return Taf.BOOLEAN
    }
}
,
Taf.ENUM = function() {
    this._clone = function() {
        return 0
    }
    ,
    this._write = function(t, e, i) {
        return t.writeInt32(e, i)
    }
    ,
    this._read = function(t, e, i) {
        return t.readInt32(e, !0, i)
    }
}
,
Taf.Vector = function(t) {
    this.proto = t,
    this.value = new Array
}
,
Taf.Vector.prototype._clone = function() {
    return new Taf.Vector(this.proto)
}
,
Taf.Vector.prototype._write = function(t, e, i) {
    return t.writeVector(e, i)
}
,
Taf.Vector.prototype._read = function(t, e, i) {
    return t.readVector(e, !0, i)
}
,
Taf.Vector.prototype._className = function() {
    return Taf.TypeHelp.VECTOR.replace("$t", this.proto._className())
}
,
Taf.Map = function(t, e) {
    this.kproto = t,
    this.vproto = e,
    this.value = new Object
}
,
Taf.Map.prototype._clone = function() {
    return new Taf.Map(this.kproto,this.vproto)
}
,
Taf.Map.prototype._write = function(t, e, i) {
    return t.writeMap(e, i)
}
,
Taf.Map.prototype._read = function(t, e, i) {
    return t.readMap(e, !0, i)
}
,
Taf.Map.prototype.put = function(t, e) {
    this.value[t] = e
}
,
Taf.Map.prototype.get = function(t) {
    return this.value[t]
}
,
Taf.Map.prototype.remove = function(t) {
    delete this.value[t]
}
,
Taf.Map.prototype.clear = function() {
    this.value = new Object
}
,
Taf.Map.prototype.size = function() {
    var t = 0;
    for (var e in this.value)
        t++;
    return t
}
,
Taf.Vector.prototype._className = function() {
    return Taf.TypeHelp.Map.replace("$k", this.kproto._className()).replace("$v", this.vproto._className())
}
;
var Taf = Taf || {};
Taf.DataHelp = {
    EN_INT8: 0,
    EN_INT16: 1,
    EN_INT32: 2,
    EN_INT64: 3,
    EN_FLOAT: 4,
    EN_DOUBLE: 5,
    EN_STRING1: 6,
    EN_STRING4: 7,
    EN_MAP: 8,
    EN_LIST: 9,
    EN_STRUCTBEGIN: 10,
    EN_STRUCTEND: 11,
    EN_ZERO: 12,
    EN_SIMPLELIST: 13
},
Taf.TypeHelp = {
    BOOLEAN: "bool",
    CHAR: "char",
    SHORT: "short",
    INT32: "int32",
    INT64: "int64",
    FLOAT: "float",
    DOUBLE: "double",
    STRING: "string",
    VECTOR: "list<$t>",
    MAP: "map<$k, $v>"
},
Taf.BinBuffer = function(t) {
    this.buf = null,
    this.vew = null,
    this.len = 0,
    this.position = 0,
    null != t && void 0 != t && t instanceof Taf.BinBuffer && (this.buf = t.buf,
    this.vew = new DataView(this.buf),
    this.len = t.length,
    this.position = t.position),
    null != t && void 0 != t && t instanceof ArrayBuffer && (this.buf = t,
    this.vew = new DataView(this.buf),
    this.len = this.vew.byteLength,
    this.position = 0),
    this.__defineGetter__("length", function() {
        return this.len
    }),
    this.__defineGetter__("buffer", function() {
        return this.buf
    })
}
,
Taf.BinBuffer.prototype._write = function(t, e, i) {
    return t.writeBytes(e, i)
}
,
Taf.BinBuffer.prototype._read = function(t, e, i) {
    return t.readBytes(e, !0, i)
}
,
Taf.BinBuffer.prototype._clone = function() {
    return new Taf.BinBuffer
}
,
Taf.BinBuffer.prototype.allocate = function(t) {
    if (t = this.position + t,
    !(null != this.buf && this.buf.length > t)) {
        var e = new ArrayBuffer(Math.max(256, 2 * t));
        null != this.buf && (new Uint8Array(e).set(new Uint8Array(this.buf)),
        this.buf = void 0),
        this.buf = e,
        this.vew = void 0,
        this.vew = new DataView(this.buf)
    }
}
,
Taf.BinBuffer.prototype.getBuffer = function() {
    var t = new ArrayBuffer(this.len);
    return new Uint8Array(t).set(new Uint8Array(this.buf,0,this.len)),
    t
}
,
Taf.BinBuffer.prototype.memset = function(t, e, i) {
    this.allocate(i),
    new Uint8Array(this.buf).set(new Uint8Array(t,e,i), this.position)
}
,
Taf.BinBuffer.prototype.writeInt8 = function(t) {
    this.allocate(1),
    this.vew.setInt8(this.position, t),
    this.position += 1,
    this.len = this.position
}
,
Taf.BinBuffer.prototype.writeUInt8 = function(t) {
    this.allocate(1),
    this.vew.setUint8(this.position++, t),
    this.len = this.position
}
,
Taf.BinBuffer.prototype.writeInt16 = function(t) {
    this.allocate(2),
    this.vew.setInt16(this.position, t),
    this.position += 2,
    this.len = this.position
}
,
Taf.BinBuffer.prototype.writeUInt16 = function(t) {
    this.allocate(2),
    this.vew.setUint16(this.position, t),
    this.position += 2,
    this.len = this.position
}
,
Taf.BinBuffer.prototype.writeInt32 = function(t) {
    this.allocate(4),
    this.vew.setInt32(this.position, t),
    this.position += 4,
    this.len = this.position
}
,
Taf.BinBuffer.prototype.writeUInt32 = function(t) {
    this.allocate(4),
    this.vew.setUint32(this.position, t),
    this.position += 4,
    this.len = this.position
}
,
Taf.BinBuffer.prototype.writeInt64 = function(t) {
    this.allocate(8),
    this.vew.setUint32(this.position, parseInt(t / 4294967296)),
    this.vew.setUint32(this.position + 4, t % 4294967296),
    this.position += 8,
    this.len = this.position
}
,
Taf.BinBuffer.prototype.writeFloat = function(t) {
    this.allocate(4),
    this.vew.setFloat32(this.position, t),
    this.position += 4,
    this.len = this.position
}
,
Taf.BinBuffer.prototype.writeDouble = function(t) {
    this.allocate(8),
    this.vew.setFloat64(this.position, t),
    this.position += 8,
    this.len = this.position
}
,
Taf.BinBuffer.prototype.writeString = function(t) {
    for (var e = [], i = 0; i < t.length; i++)
        e.push(255 & t.charCodeAt(i));
    this.allocate(e.length),
    new Uint8Array(this.buf).set(new Uint8Array(e), this.position),
    this.position += e.length,
    this.len = this.position
}
,
Taf.BinBuffer.prototype.writeBytes = function(t) {
    0 != t.length && null != t.buf && (this.allocate(t.length),
    new Uint8Array(this.buf).set(new Uint8Array(t.buf,0,t.length), this.position),
    this.position += t.length,
    this.len = this.position)
}
,
Taf.BinBuffer.prototype.readInt8 = function() {
    return this.vew.getInt8(this.position++)
}
,
Taf.BinBuffer.prototype.readInt16 = function() {
    return this.position += 2,
    this.vew.getInt16(this.position - 2)
}
,
Taf.BinBuffer.prototype.readInt32 = function() {
    return this.position += 4,
    this.vew.getInt32(this.position - 4)
}
,
Taf.BinBuffer.prototype.readUInt8 = function() {
    return this.position += 1,
    this.vew.getUint8(this.position - 1)
}
,
Taf.BinBuffer.prototype.readUInt16 = function() {
    return this.position += 2,
    this.vew.getUint16(this.position - 2)
}
,
Taf.BinBuffer.prototype.readUInt32 = function() {
    return this.position += 4,
    this.vew.getUint32(this.position - 4)
}
,
Taf.BinBuffer.prototype.readInt64 = function() {
    var t = this.vew.getUint32(this.position)
      , e = this.vew.getUint32(this.position + 4);
    return this.position += 8,
    4294967296 * t + e
}
,
Taf.BinBuffer.prototype.readFloat = function() {
    var t = this.vew.getFloat32(this.position);
    return this.position += 4,
    t
}
,
Taf.BinBuffer.prototype.readDouble = function() {
    var t = this.vew.getFloat64(this.position);
    return this.position += 8,
    t
}
,
Taf.BinBuffer.prototype.readString = function(t) {
    for (var e = [], i = 0; t > i; i++)
        e.push(String.fromCharCode(this.vew.getUint8(this.position++)));
    var r = e.join("");
    try {
        r = decodeURIComponent(escape(r))
    } catch (s) {}
    return r
}
,
Taf.BinBuffer.prototype.readBytes = function(t) {
    var e = new Taf.BinBuffer;
    return e.allocate(t),
    e.memset(this.buf, this.position, t),
    e.position = 0,
    e.len = t,
    this.position = this.position + t,
    e
}
,
Taf.JceOutputStream = function() {
    this.buf = new Taf.BinBuffer,
    this.getBinBuffer = function() {
        return this.buf
    }
    ,
    this.getBuffer = function() {
        return this.buf.getBuffer()
    }
}
,
Taf.JceOutputStream.prototype.writeTo = function(t, e) {
    15 > t ? this.buf.writeUInt8(t << 4 & 240 | e) : this.buf.writeUInt16((240 | e) << 8 | t)
}
,
Taf.JceOutputStream.prototype.writeBoolean = function(t, e) {
    this.writeInt8(t, 1 == e ? 1 : 0)
}
,
Taf.JceOutputStream.prototype.writeInt8 = function(t, e) {
    0 == e ? this.writeTo(t, Taf.DataHelp.EN_ZERO) : (this.writeTo(t, Taf.DataHelp.EN_INT8),
    this.buf.writeInt8(e))
}
,
Taf.JceOutputStream.prototype.writeInt16 = function(t, e) {
    e >= -128 && 127 >= e ? this.writeInt8(t, e) : (this.writeTo(t, Taf.DataHelp.EN_INT16),
    this.buf.writeInt16(e))
}
,
Taf.JceOutputStream.prototype.writeInt32 = function(t, e) {
    e >= -32768 && 32767 >= e ? this.writeInt16(t, e) : (this.writeTo(t, Taf.DataHelp.EN_INT32),
    this.buf.writeInt32(e))
}
,
Taf.JceOutputStream.prototype.writeInt64 = function(t, e) {
    e >= -2147483648 && 2147483647 >= e ? this.writeInt32(t, e) : (this.writeTo(t, Taf.DataHelp.EN_INT64),
    this.buf.writeInt64(e))
}
,
Taf.JceOutputStream.prototype.writeUInt8 = function(t, e) {
    this.writeInt16(t, e)
}
,
Taf.JceOutputStream.prototype.writeUInt16 = function(t, e) {
    this.writeInt32(t, e)
}
,
Taf.JceOutputStream.prototype.writeUInt32 = function(t, e) {
    this.writeInt64(t, e)
}
,
Taf.JceOutputStream.prototype.writeFloat = function(t, e) {
    0 == e ? this.writeTo(t, Taf.DataHelp.EN_ZERO) : (this.writeTo(t, Taf.DataHelp.EN_FLOAT),
    this.buf.writeFloat(e))
}
,
Taf.JceOutputStream.prototype.writeDouble = function(t, e) {
    0 == e ? this.writeTo(t, Taf.DataHelp.EN_ZERO) : (this.writeTo(t, Taf.DataHelp.EN_DOUBLE),
    this.buf.writeDouble(e))
}
,
Taf.JceOutputStream.prototype.writeStruct = function(t, e) {
    if (void 0 == e.writeTo)
        throw Error("not defined writeTo Function");
    this.writeTo(t, Taf.DataHelp.EN_STRUCTBEGIN),
    e.writeTo(this),
    this.writeTo(0, Taf.DataHelp.EN_STRUCTEND)
}
,
Taf.JceOutputStream.prototype.writeString = function(t, e) {
    var i = e;
    try {
        i = unescape(encodeURIComponent(i))
    } catch (r) {}
    i.length > 255 ? (this.writeTo(t, Taf.DataHelp.EN_STRING4),
    this.buf.writeUInt32(i.length)) : (this.writeTo(t, Taf.DataHelp.EN_STRING1),
    this.buf.writeUInt8(i.length)),
    this.buf.writeString(i)
}
,
Taf.JceOutputStream.prototype.writeBytes = function(t, e) {
    if (!(e instanceof Taf.BinBuffer))
        throw Error("value not instanceof Taf.BinBuffer");
    this.writeTo(t, Taf.DataHelp.EN_SIMPLELIST),
    this.writeTo(0, Taf.DataHelp.EN_INT8),
    this.writeInt32(0, e.length),
    this.buf.writeBytes(e)
}
,
Taf.JceOutputStream.prototype.writeVector = function(t, e) {
    this.writeTo(t, Taf.DataHelp.EN_LIST),
    this.writeInt32(0, e.value.length);
    for (var i = 0; i < e.value.length; i++)
        e.proto._write(this, 0, e.value[i])
}
,
Taf.JceOutputStream.prototype.writeMap = function(t, e) {
    this.writeTo(t, Taf.DataHelp.EN_MAP),
    this.writeInt32(0, e.size());
    for (var i in e.value)
        e.kproto._write(this, 0, i),
        e.vproto._write(this, 1, e.value[i])
}
,
Taf.JceInputStream = function(t) {
    this.buf = new Taf.BinBuffer(t)
}
,
Taf.JceInputStream.prototype.readFrom = function() {
    var t = this.buf.readUInt8()
      , e = (240 & t) >> 4
      , i = 15 & t;
    return e >= 15 && (e = this.buf.readUInt8()),
    {
        tag: e,
        type: i
    }
}
,
Taf.JceInputStream.prototype.peekFrom = function() {
    var t = this.buf.position
      , e = this.readFrom();
    return this.buf.position = t,
    {
        tag: e.tag,
        type: e.type,
        size: e.tag >= 15 ? 2 : 1
    }
}
,
Taf.JceInputStream.prototype.skipField = function(t) {
    switch (t) {
    case Taf.DataHelp.EN_INT8:
        this.buf.position += 1;
        break;
    case Taf.DataHelp.EN_INT16:
        this.buf.position += 2;
        break;
    case Taf.DataHelp.EN_INT32:
        this.buf.position += 4;
        break;
    case Taf.DataHelp.EN_STRING1:
        var e = this.buf.readUInt8();
        this.buf.position += e;
        break;
    case Taf.DataHelp.EN_STRING4:
        var i = this.buf.readInt32();
        this.buf.position += i;
        break;
    case Taf.DataHelp.EN_STRUCTBEGIN:
        this.skipToStructEnd();
        break;
    case Taf.DataHelp.EN_STRUCTEND:
    case Taf.DataHelp.EN_ZERO:
        break;
    case Taf.DataHelp.EN_MAP:
        for (var r = this.readInt32(0, !0), s = 0; 2 * r > s; ++s) {
            var n = this.readFrom();
            this.skipField(n.type)
        }
        break;
    case Taf.DataHelp.EN_SIMPLELIST:
        var n = this.readFrom();
        if (n.type != Taf.DataHelp.EN_INT8)
            throw Error("skipField with invalid type, type value: " + t + "," + n.type);
        this.buf.position += this.readInt32(0, !0);
        break;
    case Taf.DataHelp.EN_LIST:
        for (var r = this.readInt32(0, !0), s = 0; r > s; ++s) {
            var n = this.readFrom();
            this.skipField(n.type)
        }
        break;
    default:
        throw new Error("skipField with invalid type, type value: " + t)
    }
}
,
Taf.JceInputStream.prototype.skipToStructEnd = function() {
    for (; ; ) {
        var t = this.readFrom();
        if (this.skipField(t.type),
        t.type == Taf.DataHelp.EN_STRUCTEND)
            return
    }
}
,
Taf.JceInputStream.prototype.skipToTag = function(t, e) {
    for (; this.buf.position < this.buf.length; ) {
        var i = this.peekFrom();
        if (t <= i.tag || i.type == Taf.DataHelp.EN_STRUCTEND)
            return i.type == Taf.DataHelp.EN_STRUCTEND ? !1 : t == i.tag;
        this.buf.position += i.size,
        this.skipField(i.type)
    }
    if (e)
        throw Error("require field not exist, tag:" + t);
    return !1
}
,
Taf.JceInputStream.prototype.readBoolean = function(t, e, i) {
    return 1 == this.readInt8(t, e, i) ? !0 : !1
}
,
Taf.JceInputStream.prototype.readInt8 = function(t, e, i) {
    if (0 == this.skipToTag(t, e))
        return i;
    var r = this.readFrom();
    switch (r.type) {
    case Taf.DataHelp.EN_ZERO:
        return 0;
    case Taf.DataHelp.EN_INT8:
        return this.buf.readInt8()
    }
    throw Error("read int8 type mismatch, tag:" + t + ", get type:" + r.type)
}
,
Taf.JceInputStream.prototype.readInt16 = function(t, e, i) {
    if (0 == this.skipToTag(t, e))
        return i;
    var r = this.readFrom();
    switch (r.type) {
    case Taf.DataHelp.EN_ZERO:
        return 0;
    case Taf.DataHelp.EN_INT8:
        return this.buf.readInt8();
    case Taf.DataHelp.EN_INT16:
        return this.buf.readInt16()
    }
    throw Error("read int8 type mismatch, tag:" + t + ", get type:" + r.type)
}
,
Taf.JceInputStream.prototype.readInt32 = function(t, e, i) {
    if (0 == this.skipToTag(t, e))
        return i;
    var r = this.readFrom();
    switch (r.type) {
    case Taf.DataHelp.EN_ZERO:
        return 0;
    case Taf.DataHelp.EN_INT8:
        return this.buf.readInt8();
    case Taf.DataHelp.EN_INT16:
        return this.buf.readInt16();
    case Taf.DataHelp.EN_INT32:
        return this.buf.readInt32()
    }
    throw Error("read int8 type mismatch, tag:" + t + ", get type:" + r.type)
}
,
Taf.JceInputStream.prototype.readInt64 = function(t, e, i) {
    if (0 == this.skipToTag(t, e))
        return i;
    var r = this.readFrom();
    switch (r.type) {
    case Taf.DataHelp.EN_ZERO:
        return 0;
    case Taf.DataHelp.EN_INT8:
        return this.buf.readInt8();
    case Taf.DataHelp.EN_INT16:
        return this.buf.readInt16();
    case Taf.DataHelp.EN_INT32:
        return this.buf.readInt32();
    case Taf.DataHelp.EN_INT64:
        return this.buf.readInt64()
    }
    throw Error("read int64 type mismatch, tag:" + t + ", get type:" + h.type)
}
,
Taf.JceInputStream.prototype.readFloat = function(t, e, i) {
    if (0 == this.skipToTag(t, e))
        return i;
    var r = this.readFrom();
    switch (r.type) {
    case Taf.DataHelp.EN_ZERO:
        return 0;
    case Taf.DataHelp.EN_FLOAT:
        return this.buf.readFloat()
    }
    throw Error("read float type mismatch, tag:" + t + ", get type:" + h.type)
}
,
Taf.JceInputStream.prototype.readDouble = function(t, e, i) {
    if (0 == this.skipToTag(t, e))
        return i;
    var r = this.readFrom();
    switch (r.type) {
    case Taf.DataHelp.EN_ZERO:
        return 0;
    case Taf.DataHelp.EN_DOUBLE:
        return this.buf.readDouble()
    }
    throw Error("read double type mismatch, tag:" + t + ", get type:" + h.type)
}
,
Taf.JceInputStream.prototype.readUInt8 = function(t, e, i) {
    return this.readInt16(t, e, i)
}
,
Taf.JceInputStream.prototype.readUInt16 = function(t, e, i) {
    return this.readInt32(t, e, i)
}
,
Taf.JceInputStream.prototype.readUInt32 = function(t, e, i) {
    return this.readInt64(t, e, i)
}
,
Taf.JceInputStream.prototype.readStruct = function(t, e, i) {
    if (0 == this.skipToTag(t, e))
        return i;
    var r = this.readFrom();
    if (r.type != Taf.DataHelp.EN_STRUCTBEGIN)
        throw Error("read struct type mismatch, tag: " + t + ", get type:" + r.type);
    return i.readFrom(this),
    this.skipToStructEnd(),
    i
}
,
Taf.JceInputStream.prototype.readString = function(t, e, i) {
    if (0 == this.skipToTag(t, e))
        return i;
    var r = this.readFrom();
    if (r.type == Taf.DataHelp.EN_STRING1)
        return this.buf.readString(this.buf.readUInt8());
    if (r.type == Taf.DataHelp.EN_STRING4)
        return this.buf.readString(this.buf.readUInt32());
    throw Error("read 'string' type mismatch, tag: " + t + ", get type: " + r.type + ".")
}
,
Taf.JceInputStream.prototype.readString2 = function(t, e, i) {
    if (0 == this.skipToTag(t, e))
        return i;
    var r = this.readFrom();
    if (r.type == Taf.DataHelp.EN_STRING1)
        return this.buf.readBytes(this.buf.readUInt8());
    if (r.type == Taf.DataHelp.EN_STRING4)
        return this.buf.readBytes(this.buf.readUInt32());
    throw Error("read 'string' type mismatch, tag: " + t + ", get type: " + r.type + ".")
}
,
Taf.JceInputStream.prototype.readBytes = function(t, e, i) {
    if (0 == this.skipToTag(t, e))
        return i;
    var r = this.readFrom();
    if (r.type == Taf.DataHelp.EN_SIMPLELIST) {
        var s = this.readFrom();
        if (s.type != Taf.DataHelp.EN_INT8)
            throw Error("type mismatch, tag:" + t + ",type:" + r.type + "," + s.type);
        var n = this.readInt32(0, !0);
        if (0 > n)
            throw Error("invalid size, tag:" + t + ",type:" + r.type + "," + s.type);
        return this.buf.readBytes(n)
    }
    if (r.type == Taf.DataHelp.EN_LIST) {
        var n = this.readInt32(0, !0);
        return this.buf.readBytes(n)
    }
    throw Error("type mismatch, tag:" + t + ",type:" + r.type)
}
,
Taf.JceInputStream.prototype.readVector = function(t, e, i) {
    if (0 == this.skipToTag(t, e))
        return i;
    var r = this.readFrom();
    if (r.type != Taf.DataHelp.EN_LIST)
        throw Error("read 'vector' type mismatch, tag: " + t + ", get type: " + r.type);
    var s = this.readInt32(0, !0);
    if (0 > s)
        throw Error("invalid size, tag: " + t + ", type: " + r.type + ", size: " + s);
    for (var n = 0; s > n; ++n)
        i.value.push(i.proto._read(this, 0, i.proto._clone()));
    return i
}
,
Taf.JceInputStream.prototype.readMap = function(t, e, i) {
    if (0 == this.skipToTag(t, e))
        return i;
    var r = this.readFrom();
    if (r.type != Taf.DataHelp.EN_MAP)
        throw Error("read 'map' type mismatch, tag: " + t + ", get type: " + r.type);
    var s = this.readInt32(0, !0);
    if (0 > s)
        throw Error("invalid map, tag: " + t + ", size: " + s);
    for (var n = 0; s > n; n++) {
        var o = i.kproto._read(this, 0, i.kproto._clone())
          , a = i.vproto._read(this, 1, i.vproto._clone());
        i.put(o, a)
    }
    return i
}
;
var Taf = Taf || {};
Taf.Wup = function() {
    this.iVersion = 3,
    this.cPacketType = 0,
    this.iMessageType = 0,
    this.iRequestId = 0,
    this.sServantName = "",
    this.sFuncName = "",
    this.sBuffer = new Taf.BinBuffer,
    this.iTimeout = 0,
    this.context = new Taf.Map(new Taf.STRING,new Taf.STRING),
    this.status = new Taf.Map(new Taf.STRING,new Taf.STRING),
    this.data = new Taf.Map(new Taf.STRING,new Taf.Map(new Taf.STRING,new Taf.BinBuffer)),
    this.newdata = new Taf.Map(new Taf.STRING,new Taf.BinBuffer)
}
,
Taf.Wup.prototype.setVersion = function(t) {
    this.iVersion = t
}
,
Taf.Wup.prototype.getVersion = function() {
    return this.iVersion
}
,
Taf.Wup.prototype.setServant = function(t) {
    this.sServantName = t
}
,
Taf.Wup.prototype.setFunc = function(t) {
    this.sFuncName = t
}
,
Taf.Wup.prototype.setRequestId = function(t) {
    this.iRequestId = t ? t : ++this.iRequestid
}
,
Taf.Wup.prototype.getRequestId = function() {
    return this.iRequestId
}
,
Taf.Wup.prototype.setTimeOut = function(t) {
    this.iTimeout = t
}
,
Taf.Wup.prototype.getTimeOut = function() {
    return this.iTimeout
}
,
Taf.Wup.prototype.writeTo = function() {
    var t = new Taf.JceOutputStream;
    return t.writeInt16(1, this.iVersion),
    t.writeInt8(2, this.cPacketType),
    t.writeInt32(3, this.iMessageType),
    t.writeInt32(4, this.iRequestId),
    t.writeString(5, this.sServantName),
    t.writeString(6, this.sFuncName),
    t.writeBytes(7, this.sBuffer),
    t.writeInt32(8, this.iTimeout),
    t.writeMap(9, this.context),
    t.writeMap(10, this.status),
    new Taf.BinBuffer(t.getBuffer())
}
,
Taf.Wup.prototype.encode = function() {
    var t = new Taf.JceOutputStream;
    3 == this.iVersion ? t.writeMap(0, this.newdata) : t.writeMap(0, this.data),
    this.sBuffer = t.getBinBuffer();
    var e = new Taf.BinBuffer;
    e = this.writeTo();
    var i = new Taf.BinBuffer;
    return i.writeInt32(4 + e.len),
    i.writeBytes(e),
    i
}
,
Taf.Wup.prototype.writeBoolean = function(t, e) {
    var i = new Taf.JceOutputStream;
    if (i.writeBoolean(0, e),
    3 == this.iVersion)
        this.newdata.put(t, new Taf.BinBuffer(i.getBuffer()));
    else {
        var r = this.data.get(t)
          , s = TAF.TypeHelp.BOOLEAN;
        if (void 0 == r) {
            var n = new Taf.Map(Taf.STRING,Taf.STRING);
            r = n
        }
        r.put(s, new Taf.BinBuffer(i.getBuffer())),
        this.data.put(t, r)
    }
}
,
Taf.Wup.prototype.writeInt8 = function(t, e) {
    var i = new Taf.JceOutputStream;
    if (i.writeInt8(0, e),
    3 == this.iVersion)
        this.newdata.put(t, new Taf.BinBuffer(i.getBuffer()));
    else {
        var r = this.data.get(t)
          , s = TAF.TypeHelp.CHAR;
        if (void 0 == r) {
            var n = new Taf.Map(Taf.STRING,Taf.STRING);
            r = n
        }
        r.put(s, new Taf.BinBuffer(i.getBuffer())),
        this.data.put(t, r)
    }
}
,
Taf.Wup.prototype.writeInt16 = function(t, e) {
    var i = new Taf.JceOutputStream;
    if (i.writeInt16(0, e),
    3 == this.iVersion)
        this.newdata.put(t, new Taf.BinBuffer(i.getBuffer()));
    else {
        var r = this.data.get(t)
          , s = TAF.TypeHelp.SHORT;
        if (void 0 == r) {
            var n = new Taf.Map(Taf.STRING,Taf.STRING);
            r = n
        }
        r.put(s, new Uint8Array(i.getBuffer())),
        this.data.put(t, r)
    }
}
,
Taf.Wup.prototype.writeInt32 = function(t, e) {
    var i = new Taf.JceOutputStream;
    if (i.writeInt32(0, e),
    3 == this.iVersion)
        this.newdata.put(t, new Taf.BinBuffer(i.getBuffer()));
    else {
        var r = this.data.get(t)
          , s = TAF.TypeHelp.INT32;
        if (void 0 == r) {
            var n = new Taf.Map(Taf.STRING,Taf.STRING);
            r = n
        }
        r.put(s, new Uint8Array(i.getBuffer())),
        this.data.put(t, r)
    }
}
,
Taf.Wup.prototype.writeInt64 = function(t, e) {
    var i = new Taf.JceOutputStream;
    if (i.writeInt64(0, e),
    3 == this.iVersion)
        this.newdata.put(t, new Taf.BinBuffer(i.getBuffer()));
    else {
        var r = this.data.get(t)
          , s = TAF.TypeHelp.INT64;
        if (void 0 == r) {
            var n = new Taf.Map(Taf.STRING,Taf.STRING);
            r = n
        }
        r.put(s, new Uint8Array(i.getBuffer())),
        this.data.put(t, r)
    }
}
,
Taf.Wup.prototype.writeFloat = function(t, e) {
    var i = new Taf.JceOutputStream;
    if (i.writeFloat(0, e),
    3 == this.iVersion)
        this.newdata.put(t, new Taf.BinBuffer(i.getBuffer()));
    else {
        var r = this.data.get(t)
          , s = TAF.TypeHelp.FLOAT;
        if (void 0 == r) {
            var n = new Taf.Map(Taf.STRING,Taf.STRING);
            r = n
        }
        r.put(s, new Uint8Array(i.getBuffer())),
        this.data.put(t, r)
    }
}
,
Taf.Wup.prototype.writeDouble = function(t, e) {
    var i = new Taf.JceOutputStream;
    if (i.writeDouble(0, e),
    3 == this.iVersion)
        this.newdata.put(t, new Taf.BinBuffer(i.getBuffer()));
    else {
        var r = this.data.get(t)
          , s = TAF.TypeHelp.DOUBLE;
        if (void 0 == r) {
            var n = new Taf.Map(Taf.STRING,Taf.STRING);
            r = n
        }
        r.put(s, new Uint8Array(i.getBuffer())),
        this.data.put(t, r)
    }
}
,
Taf.Wup.prototype.writeString = function(t, e) {
    var i = new Taf.JceOutputStream;
    if (i.writeString(0, e),
    3 == this.iVersion)
        this.newdata.put(t, new Taf.BinBuffer(i.getBuffer()));
    else {
        var r = this.data.get(t)
          , s = Taf.TypeHelp.STRING;
        if (void 0 == r) {
            var n = new Taf.Map(Taf.STRING,Taf.STRING);
            r = n
        }
        r.put(s, new Uint8Array(i.getBuffer())),
        this.data.put(t, r)
    }
}
,
Taf.Wup.prototype.writeVector = function(t, e) {
    var i = new Taf.JceOutputStream;
    if (i.writeVector(0, e),
    3 == this.iVersion)
        this.newdata.put(t, new Taf.BinBuffer(i.getBinBuffer()));
    else {
        var r = this.data.get(t)
          , s = e._className();
        if (void 0 == r) {
            var n = new Taf.Map(Taf.STRING,Taf.STRING);
            r = n
        }
        r.put(s, new Uint8Array(i.getBuffer())),
        this.data.put(t, r)
    }
}
,
Taf.Wup.prototype.writeStruct = function(t, e) {
    var i = new Taf.JceOutputStream;
    if (i.writeStruct(0, e),
    3 == this.iVersion)
        this.newdata.put(t, new Taf.BinBuffer(i.getBuffer()));
    else {
        var r = this.data.get(t)
          , s = " ";
        if (void 0 == r) {
            var n = new Taf.Map(Taf.STRING,Taf.STRING);
            r = n
        }
        r.put(s, new Uint8Array(i.getBuffer())),
        this.data.put(t, r)
    }
}
,
Taf.Wup.prototype.writeBytes = function(t, e) {
    var i = new Taf.JceOutputStream;
    if (i.writeBytes(0, e),
    3 == this.iVersion)
        this.newdata.put(t, new Taf.BinBuffer(i.getBuffer()));
    else {
        var r = this.data.get(t)
          , s = "vec";
        if (void 0 == r) {
            var n = new Taf.Map(Taf.STRING,Taf.STRING);
            r = n
        }
        r.put(s, new Uint8Array(i.getBuffer())),
        this.data.put(t, r)
    }
}
,
Taf.Wup.prototype.writeMap = function(t, e) {
    var i = new Taf.JceOutputStream;
    if (i.writeMap(0, e),
    3 == this.iVersion)
        this.newdata.put(t, new Taf.BinBuffer(i.getBuffer()));
    else {
        var r = this.data.get(t)
          , s = Taf.Util.getClassType(e);
        if (void 0 == r) {
            var n = new Taf.Map(Taf.STRING,Taf.STRING);
            r = n
        }
        r.put(s, new Uint8Array(i.getBuffer())),
        this.data.put(t, r)
    }
}
,
Taf.Wup.prototype.readFrom = function(t) {
    this.iVersion = t.readInt16(1, !0),
    this.cPacketType = t.readInt8(2, !0),
    this.iMessageType = t.readInt32(3, !0),
    this.iRequestId = t.readInt32(4, !0),
    this.sServantName = t.readString(5, !0),
    this.sFuncName = t.readString(6, !0),
    this.sBuffer = t.readBytes(7, !0),
    this.iTimeout = t.readInt32(8, !0),
    this.context = t.readMap(9, !0),
    this.status = t.readMap(10, !0)
}
,
Taf.Wup.prototype.decode = function(t) {
    var e = new Taf.JceInputStream(t)
      , i = e.buf.vew.getInt32(e.buf.position);
    if (4 > i)
        throw Error("packet length too short");
    e.buf.position += 4,
    this.readFrom(e),
    e = new Taf.JceInputStream(this.sBuffer.getBuffer()),
    3 == this.iVersion ? (this.newdata.clear(),
    e.readMap(0, !0, this.newdata)) : (this.data.clear(),
    e.readMap(0, !0, this.newdata))
}
,
Taf.Wup.prototype.readBoolean = function(t) {
    var e, i;
    if (3 == this.iVersion) {
        if (e = this.newdata.get(t),
        void 0 == e)
            throw Error("UniAttribute not found key:" + t);
        var r = new Taf.JceInputStream(e.buffer);
        i = r.readBoolean(0, !0, i)
    } else {
        if (e = this.newdata.get(t),
        void 0 == e)
            throw Error("UniAttribute not found key:" + t);
        var s = Taf.TypeHelp.BOOLEAN
          , n = e.get(s);
        if (void 0 == n)
            throw Error("UniAttribute not found type:" + s);
        var r = new Taf.JceInputStream(n);
        i = r.readBoolean(0, !0, i)
    }
    return i
}
,
Taf.Wup.prototype.readInt8 = function(t) {
    var e, i;
    if (3 == this.iVersion) {
        if (e = this.newdata.get(t),
        void 0 == e)
            throw Error("UniAttribute not found key:" + t);
        var r = new Taf.JceInputStream(e.buffer);
        i = r.readInt8(0, !0, i)
    } else {
        if (e = this.newdata.get(t),
        void 0 == e)
            throw Error("UniAttribute not found key:" + t);
        var s = Taf.TypeHelp.CHAR
          , n = e.get(s);
        if (void 0 == n)
            throw Error("UniAttribute not found type:" + s);
        var r = new Taf.JceInputStream(n);
        i = r.readInt8(0, !0, i)
    }
    return i
}
,
Taf.Wup.prototype.readInt16 = function(t) {
    var e, i;
    if (3 == this.iVersion) {
        if (e = this.newdata.get(t),
        void 0 == e)
            throw Error("UniAttribute not found key:" + t);
        var r = new Taf.JceInputStream(e.buffer);
        i = r.readInt16(0, !0, i)
    } else {
        if (e = this.newdata.get(t),
        void 0 == e)
            throw Error("UniAttribute not found key:" + t);
        var s = Taf.TypeHelp.SHORT
          , n = e.get(s)
          , r = new Taf.JceInputStream(n);
        if (void 0 == n)
            throw Error("UniAttribute not found type:" + s);
        i = r.readInt16(0, !0, i)
    }
    return i
}
,
Taf.Wup.prototype.readInt32 = function(t) {
    var e, i;
    if (3 == this.iVersion) {
        if (e = this.newdata.get(t),
        void 0 == e)
            throw Error("UniAttribute not found key:" + t);
        var r = new Taf.JceInputStream(e.buffer);
        i = r.readInt32(0, !0, i)
    } else {
        if (e = this.newdata.get(t),
        void 0 == e)
            throw Error("UniAttribute not found key:" + t);
        var s = Taf.TypeHelp.INT32
          , n = e.get(s);
        if (void 0 == n)
            throw Error("UniAttribute not found type:" + s);
        var r = new Taf.JceInputStream(n);
        i = r.readInt32(0, !0, i)
    }
    return i
}
,
Taf.Wup.prototype.readInt64 = function(t) {
    var e, i;
    if (3 == this.iVersion) {
        if (e = this.newdata.get(t),
        void 0 == e)
            throw Error("UniAttribute not found key:" + t);
        var r = new Taf.JceInputStream(e.buffer);
        i = r.readInt64(0, !0, i)
    } else {
        if (e = this.newdata.get(t),
        void 0 == e)
            throw Error("UniAttribute not found key:" + t);
        var s = Taf.TypeHelp.INT64
          , n = e.get(s);
        if (void 0 == n)
            throw Error("UniAttribute not found type:" + s);
        var r = new Taf.JceInputStream(n);
        i = r.readInt64(0, !0, i)
    }
    return i
}
,
Taf.Wup.prototype.readFloat = function(t) {
    var e, i;
    if (3 == this.iVersion) {
        if (e = this.newdata.get(t),
        void 0 == e)
            throw Error("UniAttribute not found key:" + t);
        var r = new Taf.JceInputStream(e.buffer);
        i = r.readFloat(0, !0, i)
    } else {
        if (e = this.newdata.get(t),
        void 0 == e)
            throw Error("UniAttribute not found key:" + t);
        var s = Taf.TypeHelp.FLOAT
          , n = e.get(s);
        if (void 0 == n)
            throw Error("UniAttribute not found type:" + s);
        var r = new Taf.JceInputStream(n);
        i = r.readFloat(0, !0, i)
    }
    return i
}
,
Taf.Wup.prototype.readDouble = function(t) {
    var e;
    if (3 == this.iVersion) {
        if (e = this.newdata.get(t),
        void 0 == e)
            throw Error("UniAttribute not found key:" + t);
        var i = new Taf.JceInputStream(e.buffer);
        def = i.readDouble(0, !0, def)
    } else {
        if (e = this.newdata.get(t),
        void 0 == e)
            throw Error("UniAttribute not found key:" + t);
        var r = Taf.TypeHelp.DOUBLE
          , s = e.get(r);
        if (void 0 == s)
            throw Error("UniAttribute not found type:" + r);
        var i = new Taf.JceInputStream(s);
        def = i.readDouble(0, !0, def)
    }
    return def
}
,
Taf.Wup.prototype.readVector = function(t, e, i) {
    var r;
    if (3 == this.iVersion) {
        if (r = this.newdata.get(t),
        void 0 == r)
            throw Error("UniAttribute not found key:" + t);
        var s = new Taf.JceInputStream(r.buffer);
        e = s.readVector(0, !0, e)
    } else {
        if (r = this.newdata.get(t),
        void 0 == r)
            throw Error("UniAttribute not found key:" + t);
        var n = r.get(i);
        if (void 0 == n)
            throw Error("UniAttribute not found type:" + i);
        var s = new Taf.JceInputStream(n);
        e = s.readVector(0, !0, e)
    }
    return e
}
,
Taf.Wup.prototype.readStruct = function(t, e, i) {
    var r;
    if (3 == this.iVersion) {
        if (r = this.newdata.get(t),
        void 0 == r)
            throw Error("UniAttribute not found key:" + t);
        var s = new Taf.JceInputStream(r.buffer);
        e = s.readStruct(0, !0, e)
    } else {
        if (r = this.newdata.get(t),
        void 0 == r)
            throw Error("UniAttribute not found key:" + t);
        var n = r.get(i);
        if (void 0 == n)
            throw Error("UniAttribute not found type:" + i);
        var s = new Taf.JceInputStream(n);
        e = s.readStruct(0, !0, e)
    }
    return e
}
,
Taf.Wup.prototype.readMap = function(t, e, i) {
    var r;
    if (3 == this.iVersion) {
        if (r = this.newdata.get(t),
        void 0 == r)
            throw Error("UniAttribute not found key:" + t);
        var s = new Taf.JceInputStream(r.buffer);
        e = s.readMap(0, !0, e)
    } else {
        if (r = this.newdata.get(t),
        void 0 == r)
            throw Error("UniAttribute not found key:" + t);
        var n = r.get(i);
        if (void 0 == n)
            throw Error("UniAttribute not found type:" + i);
        var s = new Taf.JceInputStream(n);
        e = s.readMap(0, !0, e)
    }
    return e
}
,
Taf.Wup.prototype.readBytes = function(t, e, i) {
    var r;
    if (3 == this.iVersion) {
        if (r = this.newdata.get(t),
        void 0 == r)
            throw Error("UniAttribute not found key:" + t);
        var s = new Taf.JceInputStream(r.buffer);
        e = s.readBytes(0, !0, e)
    } else {
        if (r = this.newdata.get(t),
        void 0 == r)
            throw Error("UniAttribute not found key:" + t);
        var n = r.get(i);
        if (void 0 == n)
            throw Error("UniAttribute not found type:" + i);
        var s = new Taf.JceInputStream(n);
        e = s.readBytes(0, !0, e)
    }
    return e
}
;
var Taf = Taf || {};
Taf.Util = Taf.Util || {},
Taf.Util.jcestream = function(t) {
    if (null == t || void 0 == t)
        return void console.log("Taf.Util.jcestream::value is null or undefined");
    if (!(t instanceof ArrayBuffer))
        return void console.log("Taf.Util.jcestream::value is not ArrayBuffer");
    for (var e = new Uint8Array(t), i = "", r = 0; r < e.length; r++)
        0 != r && r % 16 == 0 ? i += "\n" : 0 != r && (i += " "),
        i += (e[r] > 15 ? "" : "0") + e[r].toString(16);
    console.log(i.toUpperCase())
}
,
Taf.Util.str2ab = function(t) {
    var e, i = t.length, r = new Array(i);
    for (e = 0; i > e; ++e)
        r[e] = t.charCodeAt(e);
    return new Uint8Array(r).buffer
}
,
Taf.Util.ajax = function(t, e, i, r) {
    var s = new XMLHttpRequest;
    s.overrideMimeType("text/plain; charset=x-user-defined");
    var n = function() {
        4 === s.readyState && (200 === s.status || 304 === s.status ? i(Taf.Util.str2ab(s.response)) : r(s.status),
        s.removeEventListener("readystatechange", n),
        s = void 0)
    };
    s.addEventListener("readystatechange", n),
    s.open("post", t),
    s.send(e)
}
;
var HUYA = HUYA || {};
HUYA.EWebSocketCommandType = {
    EWSCmd_NULL: 0,
    EWSCmd_RegisterReq: 1,
    EWSCmd_RegisterRsp: 2,
    EWSCmd_WupReq: 3,
    EWSCmd_WupRsp: 4,
    EWSCmdC2S_HeartBeat: 5,
    EWSCmdS2C_HeartBeatAck: 6,
    EWSCmdS2C_MsgPushReq: 7,
    EWSCmdC2S_DeregisterReq: 8,
    EWSCmdS2C_DeRegisterRsp: 9,
    EWSCmdC2S_VerifyCookieReq: 10,
    EWSCmdS2C_VerifyCookieRsp: 11,
    EWSCmdC2S_VerifyHuyaTokenReq: 12,
    EWSCmdS2C_VerifyHuyaTokenRsp: 13
},
HUYA.ELiveSource = {
    PC_YY: 0,
    PC_HUYA: 1,
    MOBILE_HUYA: 2,
    WEB_HUYA: 3
},
HUYA.EGender = {
    MALE: 0,
    FEMALE: 1
},
HUYA.EClientTemplateType = {
    TPL_PC: 64,
    TPL_WEB: 32,
    TPL_JIEDAI: 16,
    TPL_TEXAS: 8,
    TPL_MATCH: 4,
    TPL_HUYAAPP: 2,
    TPL_MIRROR: 1
},
HUYA.TemplateType = {
    PRIMARY: 1,
    RECEPTION: 2
},
HUYA.EStreamLineType = {
    STREAM_LINE_OLD_YY: 0,
    STREAM_LINE_WS: 1,
    STREAM_LINE_NEW_YY: 2,
    STREAM_LINE_AL: 3,
    STREAM_LINE_HUYA: 4
},
HUYA.eUserOperation = {
    USER_IN: 1,
    USER_OUT: 2,
    USER_MOVE: 3
},
HUYA.WebSocketCommand = function() {
    this.iCmdType = 0,
    this.vData = new Taf.BinBuffer
}
,
HUYA.WebSocketCommand.prototype._clone = function() {
    return new HUYA.WebSocketCommand
}
,
HUYA.WebSocketCommand.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.WebSocketCommand.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.WebSocketCommand.prototype.writeTo = function(t) {
    t.writeInt32(0, this.iCmdType),
    t.writeBytes(1, this.vData)
}
,
HUYA.WebSocketCommand.prototype.readFrom = function(t) {
    this.iCmdType = t.readInt32(0, !1, this.iCmdType),
    this.vData = t.readBytes(1, !1, this.vData)
}
,
HUYA.WSRegisterRsp = function() {
    this.iResCode = 0,
    this.lRequestId = 0,
    this.sMessage = ""
}
,
HUYA.WSRegisterRsp.prototype._clone = function() {
    return new HUYA.WSRegisterRsp
}
,
HUYA.WSRegisterRsp.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.WSRegisterRsp.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.WSRegisterRsp.prototype.writeTo = function(t) {
    t.writeInt32(0, this.iResCode),
    t.writeInt64(1, this.lRequestId),
    t.writeString(2, this.sMessage)
}
,
HUYA.WSRegisterRsp.prototype.readFrom = function(t) {
    this.iResCode = t.readInt32(0, !1, this.iResCode),
    this.lRequestId = t.readInt64(1, !1, this.lRequestId),
    this.sMessage = t.readString(2, !1, this.sMessage)
}
,
HUYA.WSPushMessage = function() {
    this.ePushType = 0,
    this.iUri = 0,
    this.sMsg = new Taf.BinBuffer,
    this.iProtocolType = 0
}
,
HUYA.WSPushMessage.prototype._clone = function() {
    return new HUYA.WSPushMessage
}
,
HUYA.WSPushMessage.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.WSPushMessage.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.WSPushMessage.prototype.writeTo = function(t) {
    t.writeInt32(0, this.ePushType),
    t.writeInt64(1, this.iUri),
    t.writeBytes(2, this.sMsg),
    t.writeInt32(3, this.iProtocolType)
}
,
HUYA.WSPushMessage.prototype.readFrom = function(t) {
    this.ePushType = t.readInt32(0, !1, this.ePushType),
    this.iUri = t.readInt64(1, !1, this.iUri),
    this.sMsg = t.readBytes(2, !1, this.sMsg),
    this.iProtocolType = t.readInt32(3, !1, this.iProtocolType)
}
,
HUYA.WSHeartBeat = function() {
    this.iState = 0
}
,
HUYA.WSHeartBeat.prototype._clone = function() {
    return new HUYA.WSHeartBeat
}
,
HUYA.WSHeartBeat.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.WSHeartBeat.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.WSHeartBeat.prototype.writeTo = function(t) {
    t.writeInt32(0, this.iState)
}
,
HUYA.WSHeartBeat.prototype.readFrom = function(t) {
    this.iState = t.readInt32(0, !1, this.iState)
}
,
HUYA.WSUserInfo = function() {
    this.lUid = 0,
    this.bAnonymous = !0,
    this.sGuid = "",
    this.sToken = "",
    this.lTid = 0,
    this.lSid = 0,
    this.lGroupId = 0,
    this.lGroupType = 0
}
,
HUYA.WSUserInfo.prototype._clone = function() {
    return new HUYA.WSUserInfo
}
,
HUYA.WSUserInfo.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.WSUserInfo.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.WSUserInfo.prototype.writeTo = function(t) {
    t.writeInt64(0, this.lUid),
    t.writeBoolean(1, this.bAnonymous),
    t.writeString(2, this.sGuid),
    t.writeString(3, this.sToken),
    t.writeInt64(4, this.lTid),
    t.writeInt64(5, this.lSid),
    t.writeInt64(6, this.lGroupId),
    t.writeInt64(7, this.lGroupType)
}
,
HUYA.WSUserInfo.prototype.readFrom = function(t) {
    this.lUid = t.readInt64(0, !1, this.lUid),
    this.bAnonymous = t.readBoolean(1, !1, this.bAnonymous),
    this.sGuid = t.readString(2, !1, this.sGuid),
    this.sToken = t.readString(3, !1, this.sToken),
    this.lTid = t.readInt64(4, !1, this.lTid),
    this.lSid = t.readInt64(5, !1, this.lSid),
    this.lGroupId = t.readInt64(6, !1, this.lGroupId),
    this.lGroupType = t.readInt64(7, !1, this.lGroupType)
}
,
HUYA.WSVerifyCookieReq = function() {
    this.lUid = 0,
    this.sUA = "",
    this.sCookie = ""
}
,
HUYA.WSVerifyCookieReq.prototype._clone = function() {
    return new HUYA.WSVerifyCookieReq
}
,
HUYA.WSVerifyCookieReq.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.WSVerifyCookieReq.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.WSVerifyCookieReq.prototype.writeTo = function(t) {
    t.writeInt64(0, this.lUid),
    t.writeString(1, this.sUA),
    t.writeString(2, this.sCookie)
}
,
HUYA.WSVerifyCookieReq.prototype.readFrom = function(t) {
    this.lUid = t.readInt64(0, !1, this.lUid),
    this.sUA = t.readString(1, !1, this.sUA),
    this.sCookie = t.readString(2, !1, this.sCookie)
}
,
HUYA.WSVerifyCookieRsp = function() {
    this.iValidate = 0
}
,
HUYA.WSVerifyCookieRsp.prototype._clone = function() {
    return new HUYA.WSVerifyCookieRsp
}
,
HUYA.WSVerifyCookieRsp.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.WSVerifyCookieRsp.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.WSVerifyCookieRsp.prototype.writeTo = function(t) {
    t.writeInt32(0, this.iValidate)
}
,
HUYA.WSVerifyCookieRsp.prototype.readFrom = function(t) {
    this.iValidate = t.readInt32(0, !1, this.iValidate)
}
,
HUYA.UserId = function() {
    this.lUid = 0,
    this.sGuid = "",
    this.sToken = "",
    this.sHuYaUA = "",
    this.sCookie = ""
}
,
HUYA.UserId.prototype._clone = function() {
    return new HUYA.UserId
}
,
HUYA.UserId.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.UserId.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.UserId.prototype.writeTo = function(t) {
    t.writeInt64(0, this.lUid),
    t.writeString(1, this.sGuid),
    t.writeString(2, this.sToken),
    t.writeString(3, this.sHuYaUA),
    t.writeString(4, this.sCookie)
}
,
HUYA.UserId.prototype.readFrom = function(t) {
    this.lUid = t.readInt64(0, !1, this.lUid),
    this.sGuid = t.readString(1, !1, this.sGuid),
    this.sToken = t.readString(2, !1, this.sToken),
    this.sHuYaUA = t.readString(3, !1, this.sHuYaUA),
    this.sCookie = t.readString(4, !1, this.sCookie)
}
,
HUYA.UserEventReq = function() {
    this.tId = new HUYA.UserId,
    this.lTid = 0,
    this.lSid = 0,
    this.eOp = 0,
    this.sChan = "",
    this.eSource = 0,
    this.lPid = 0,
    this.bWatchVideo = !1,
    this.bAnonymous = !1,
    this.eTemplateType = HUYA.TemplateType.PRIMARY,
    this.sTraceSource = ""
}
,
HUYA.UserEventReq.prototype._clone = function() {
    return new HUYA.UserEventReq
}
,
HUYA.UserEventReq.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.UserEventReq.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.UserEventReq.prototype.writeTo = function(t) {
    t.writeStruct(0, this.tId),
    t.writeInt64(1, this.lTid),
    t.writeInt64(2, this.lSid),
    t.writeInt32(4, this.eOp),
    t.writeString(5, this.sChan),
    t.writeInt32(6, this.eSource),
    t.writeInt64(7, this.lPid),
    t.writeBoolean(8, this.bWatchVideo),
    t.writeBoolean(9, this.bAnonymous),
    t.writeInt32(10, this.eTemplateType),
    t.writeString(11, this.sTraceSource)
}
,
HUYA.UserEventReq.prototype.readFrom = function(t) {
    this.tId = t.readStruct(0, !1, this.tId),
    this.lTid = t.readInt64(1, !1, this.lTid),
    this.lSid = t.readInt64(2, !1, this.lSid),
    this.eOp = t.readInt32(4, !1, this.eOp),
    this.sChan = t.readString(5, !1, this.sChan),
    this.eSource = t.readInt32(6, !1, this.eSource),
    this.lPid = t.readInt64(7, !1, this.lPid),
    this.bWatchVideo = t.readBoolean(8, !1, this.bWatchVideo),
    this.bAnonymous = t.readBoolean(9, !1, this.bAnonymous),
    this.eTemplateType = t.readInt32(10, !1, this.eTemplateType),
    this.sTraceSource = t.readString(11, !1, this.sTraceSource)
}
,
HUYA.UserEventRsp = function() {
    this.lTid = 0,
    this.lSid = 0,
    this.iUserHeartBeatInterval = 60,
    this.iPresentHeartBeatInterval = 60
}
,
HUYA.UserEventRsp.prototype._clone = function() {
    return new HUYA.UserEventRsp
}
,
HUYA.UserEventRsp.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.UserEventRsp.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.UserEventRsp.prototype.writeTo = function(t) {
    t.writeInt64(0, this.lTid),
    t.writeInt64(1, this.lSid),
    t.writeInt32(2, this.iUserHeartBeatInterval),
    t.writeInt32(3, this.iPresentHeartBeatInterval)
}
,
HUYA.UserEventRsp.prototype.readFrom = function(t) {
    this.lTid = t.readInt64(0, !1, this.lTid),
    this.lSid = t.readInt64(1, !1, this.lSid),
    this.iUserHeartBeatInterval = t.readInt32(2, !1, this.iUserHeartBeatInterval),
    this.iPresentHeartBeatInterval = t.readInt32(3, !1, this.iPresentHeartBeatInterval)
}
,
HUYA.UserHeartBeatReq = function() {
    this.tId = new HUYA.UserId,
    this.lTid = 0,
    this.lSid = 0,
    this.lShortTid = 0,
    this.lPid = 0,
    this.bWatchVideo = !1,
    this.eLineType = HUYA.EStreamLineType.STREAM_LINE_OLD_YY,
    this.iFps = 0,
    this.iAttendee = 0,
    this.iBandwidth = 0,
    this.iLastHeartElapseTime = 0
}
,
HUYA.UserHeartBeatReq.prototype._clone = function() {
    return new HUYA.UserHeartBeatReq
}
,
HUYA.UserHeartBeatReq.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.UserHeartBeatReq.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.UserHeartBeatReq.prototype.writeTo = function(t) {
    t.writeStruct(0, this.tId),
    t.writeInt64(1, this.lTid),
    t.writeInt64(2, this.lSid),
    t.writeInt64(3, this.lShortTid),
    t.writeInt64(4, this.lPid),
    t.writeBoolean(5, this.bWatchVideo),
    t.writeInt32(6, this.eLineType),
    t.writeInt32(7, this.iFps),
    t.writeInt32(8, this.iAttendee),
    t.writeInt32(9, this.iBandwidth),
    t.writeInt32(10, this.iLastHeartElapseTime)
}
,
HUYA.UserHeartBeatReq.prototype.readFrom = function(t) {
    this.tId = t.readStruct(0, !1, this.tId),
    this.lTid = t.readInt64(1, !1, this.lTid),
    this.lSid = t.readInt64(2, !1, this.lSid),
    this.lShortTid = t.readInt64(3, !1, this.lShortTid),
    this.lPid = t.readInt64(4, !1, this.lPid),
    this.bWatchVideo = t.readBoolean(5, !1, this.bWatchVideo),
    this.eLineType = t.readInt32(6, !1, this.eLineType),
    this.iFps = t.readInt32(7, !1, this.iFps),
    this.iAttendee = t.readInt32(8, !1, this.iAttendee),
    this.iBandwidth = t.readInt32(9, !1, this.iBandwidth),
    this.iLastHeartElapseTime = t.readInt32(10, !1, this.iLastHeartElapseTime)
}
,
HUYA.UserHeartBeatRsp = function() {
    this.iRet = 0
}
,
HUYA.UserHeartBeatRsp.prototype._clone = function() {
    return new HUYA.UserHeartBeatRsp
}
,
HUYA.UserHeartBeatRsp.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.UserHeartBeatRsp.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.UserHeartBeatRsp.prototype.writeTo = function(t) {
    t.writeInt32(0, this.iRet)
}
,
HUYA.UserHeartBeatRsp.prototype.readFrom = function(t) {
    this.iRet = t.readInt32(0, !1, this.iRet)
}
,
HUYA.UserChannelReq = function() {
    this.tId = new HUYA.UserId,
    this.lTopcid = 0,
    this.lSubcid = 0,
    this.sSendContent = ""
}
,
HUYA.UserChannelReq.prototype._clone = function() {
    return new HUYA.UserChannelReq
}
,
HUYA.UserChannelReq.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.UserChannelReq.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.UserChannelReq.prototype.writeTo = function(t) {
    t.writeStruct(0, this.tId),
    t.writeInt64(1, this.lTopcid),
    t.writeInt64(2, this.lSubcid),
    t.writeString(3, this.sSendContent)
}
,
HUYA.UserChannelReq.prototype.readFrom = function(t) {
    this.tId = t.readStruct(0, !1, this.tId),
    this.lTopcid = t.readInt64(1, !1, this.lTopcid),
    this.lSubcid = t.readInt64(2, !1, this.lSubcid),
    this.sSendContent = t.readString(3, !1, this.sSendContent)
}
,
HUYA.GetLivingInfoReq = function() {
    this.tId = new HUYA.UserId,
    this.lTopSid = 0,
    this.lSubSid = 0,
    this.lPresenterUid = 0,
    this.sTraceSource = ""
}
,
HUYA.GetLivingInfoReq.prototype._clone = function() {
    return new HUYA.GetLivingInfoReq
}
,
HUYA.GetLivingInfoReq.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.GetLivingInfoReq.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.GetLivingInfoReq.prototype.writeTo = function(t) {
    t.writeStruct(0, this.tId),
    t.writeInt64(1, this.lTopSid),
    t.writeInt64(2, this.lSubSid),
    t.writeInt64(3, this.lPresenterUid),
    t.writeString(4, this.sTraceSource)
}
,
HUYA.GetLivingInfoReq.prototype.readFrom = function(t) {
    this.tId = t.readStruct(0, !1, this.tId),
    this.lTopSid = t.readInt64(1, !1, this.lTopSid),
    this.lSubSid = t.readInt64(2, !1, this.lSubSid),
    this.lPresenterUid = t.readInt64(3, !1, this.lPresenterUid),
    this.sTraceSource = t.readString(4, !1, this.sTraceSource)
}
,
HUYA.GetLivingInfoRsp = function() {
    this.bIsLiving = 0,
    this.tNotice = new HUYA.BeginLiveNotice,
    this.tStreamSettingNotice = new HUYA.StreamSettingNotice,
    this.bIsSelfLiving = 0
}
,
HUYA.GetLivingInfoRsp.prototype._clone = function() {
    return new HUYA.GetLivingInfoRsp
}
,
HUYA.GetLivingInfoRsp.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.GetLivingInfoRsp.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.GetLivingInfoRsp.prototype.writeTo = function(t) {
    t.writeInt32(0, this.bIsLiving),
    t.writeStruct(1, this.tNotice),
    t.writeStruct(2, this.tStreamSettingNotice),
    t.writeInt32(3, this.bIsSelfLiving)
}
,
HUYA.GetLivingInfoRsp.prototype.readFrom = function(t) {
    this.bIsLiving = t.readInt32(0, !1, this.bIsLiving),
    this.tNotice = t.readStruct(1, !1, this.tNotice),
    this.tStreamSettingNotice = t.readStruct(2, !1, this.tStreamSettingNotice),
    this.bIsSelfLiving = t.readInt32(3, !1, this.bIsSelfLiving)
}
,
HUYA.StreamInfo = function() {
    this.sCdnType = "",
    this.iIsMaster = 0,
    this.lChannelId = 0,
    this.lSubChannelId = 0,
    this.lPresenterUid = 0,
    this.sStreamName = "",
    this.sFlvUrl = "",
    this.sFlvUrlSuffix = "",
    this.sFlvAntiCode = "",
    this.sHlsUrl = "",
    this.sHlsUrlSuffix = "",
    this.sHlsAntiCode = "",
    this.iLineIndex = 0,
    this.iIsMultiStream = 0,
    this.iPCPriorityRate = 0,
    this.iWebPriorityRate = 0,
    this.iMobilePriorityRate = 0
}
,
HUYA.StreamInfo.prototype._clone = function() {
    return new HUYA.StreamInfo
}
,
HUYA.StreamInfo.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.StreamInfo.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.StreamInfo.prototype.writeTo = function(t) {
    t.writeString(0, this.sCdnType),
    t.writeInt32(1, this.iIsMaster),
    t.writeInt64(2, this.lChannelId),
    t.writeInt64(3, this.lSubChannelId),
    t.writeInt64(4, this.lPresenterUid),
    t.writeString(5, this.sStreamName),
    t.writeString(6, this.sFlvUrl),
    t.writeString(7, this.sFlvUrlSuffix),
    t.writeString(8, this.sFlvAntiCode),
    t.writeString(9, this.sHlsUrl),
    t.writeString(10, this.sHlsUrlSuffix),
    t.writeString(11, this.sHlsAntiCode),
    t.writeInt32(12, this.iLineIndex),
    t.writeInt32(13, this.iIsMultiStream),
    t.writeInt32(14, this.iPCPriorityRate),
    t.writeInt32(15, this.iWebPriorityRate),
    t.writeInt32(16, this.iMobilePriorityRate)
}
,
HUYA.StreamInfo.prototype.readFrom = function(t) {
    this.sCdnType = t.readString(0, !1, this.sCdnType),
    this.iIsMaster = t.readInt32(1, !1, this.iIsMaster),
    this.lChannelId = t.readInt64(2, !1, this.lChannelId),
    this.lSubChannelId = t.readInt64(3, !1, this.lSubChannelId),
    this.lPresenterUid = t.readInt64(4, !1, this.lPresenterUid),
    this.sStreamName = t.readString(5, !1, this.sStreamName),
    this.sFlvUrl = t.readString(6, !1, this.sFlvUrl),
    this.sFlvUrlSuffix = t.readString(7, !1, this.sFlvUrlSuffix),
    this.sFlvAntiCode = t.readString(8, !1, this.sFlvAntiCode),
    this.sHlsUrl = t.readString(9, !1, this.sHlsUrl),
    this.sHlsUrlSuffix = t.readString(10, !1, this.sHlsUrlSuffix),
    this.sHlsAntiCode = t.readString(11, !1, this.sHlsAntiCode),
    this.iLineIndex = t.readInt32(12, !1, this.iLineIndex),
    this.iIsMultiStream = t.readInt32(13, !1, this.iIsMultiStream),
    this.iPCPriorityRate = t.readInt32(14, !1, this.iPCPriorityRate),
    this.iWebPriorityRate = t.readInt32(15, !1, this.iWebPriorityRate),
    this.iMobilePriorityRate = t.readInt32(16, !1, this.iMobilePriorityRate)
}
,
HUYA.MultiStreamInfo = function() {
    this.sDisplayName = "",
    this.iBitRate = 0,
    this.iCodecType = 0,
    this.iCompatibleFlag = 0
}
,
HUYA.MultiStreamInfo.prototype._clone = function() {
    return new HUYA.MultiStreamInfo
}
,
HUYA.MultiStreamInfo.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.MultiStreamInfo.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.MultiStreamInfo.prototype.writeTo = function(t) {
    t.writeString(0, this.sDisplayName),
    t.writeInt32(1, this.iBitRate),
    t.writeInt32(2, this.iCodecType),
    t.writeInt32(3, this.iCompatibleFlag)
}
,
HUYA.MultiStreamInfo.prototype.readFrom = function(t) {
    this.sDisplayName = t.readString(0, !1, this.sDisplayName),
    this.iBitRate = t.readInt32(1, !1, this.iBitRate),
    this.iCodecType = t.readInt32(2, !1, this.iCodecType),
    this.iCompatibleFlag = t.readInt32(3, !1, this.iCompatibleFlag)
}
,
HUYA.StreamSettingNotice = function() {
    this.lPresenterUid = 0,
    this.iBitRate = 0,
    this.iResolution = 0,
    this.iFrameRate = 0,
    this.lLiveId = 0,
    this.sDisplayName = ""
}
,
HUYA.StreamSettingNotice.prototype._clone = function() {
    return new HUYA.StreamSettingNotice
}
,
HUYA.StreamSettingNotice.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.StreamSettingNotice.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.StreamSettingNotice.prototype.writeTo = function(t) {
    t.writeInt64(0, this.lPresenterUid),
    t.writeInt32(1, this.iBitRate),
    t.writeInt32(2, this.iResolution),
    t.writeInt32(3, this.iFrameRate),
    t.writeInt64(4, this.lLiveId),
    t.writeString(5, this.sDisplayName)
}
,
HUYA.StreamSettingNotice.prototype.readFrom = function(t) {
    this.lPresenterUid = t.readInt64(0, !1, this.lPresenterUid),
    this.iBitRate = t.readInt32(1, !1, this.iBitRate),
    this.iResolution = t.readInt32(2, !1, this.iResolution),
    this.iFrameRate = t.readInt32(3, !1, this.iFrameRate),
    this.lLiveId = t.readInt64(4, !1, this.lLiveId),
    this.sDisplayName = t.readString(5, !1, this.sDisplayName)
}
,
HUYA.LiveLaunchReq = function() {
    this.tId = new HUYA.UserId,
    this.tLiveUB = new HUYA.LiveUserbase
}
,
HUYA.LiveLaunchReq.prototype._clone = function() {
    return new HUYA.LiveLaunchReq
}
,
HUYA.LiveLaunchReq.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.LiveLaunchReq.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.LiveLaunchReq.prototype.writeTo = function(t) {
    t.writeStruct(0, this.tId),
    t.writeStruct(1, this.tLiveUB)
}
,
HUYA.LiveLaunchReq.prototype.readFrom = function(t) {
    this.tId = t.readStruct(0, !1, this.tId),
    this.tLiveUB = t.readStruct(1, !1, this.tLiveUB)
}
,
HUYA.LiveLaunchRsp = function() {
    this.sGuid = "",
    this.iTime = 0,
    this.vProxyList = new Taf.Vector(new HUYA.LiveProxyValue),
    this.eAccess = 0
}
,
HUYA.LiveLaunchRsp.prototype._clone = function() {
    return new HUYA.LiveLaunchRsp
}
,
HUYA.LiveLaunchRsp.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.LiveLaunchRsp.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.LiveLaunchRsp.prototype.writeTo = function(t) {
    t.writeString(0, this.sGuid),
    t.writeInt32(1, this.iTime),
    t.writeVector(2, this.vProxyList),
    t.writeInt32(3, this.eAccess)
}
,
HUYA.LiveLaunchRsp.prototype.readFrom = function(t) {
    this.sGuid = t.readString(0, !1, this.sGuid),
    this.iTime = t.readInt32(1, !1, this.iTime),
    this.vProxyList = t.readVector(2, !1, this.vProxyList),
    this.eAccess = t.readInt32(3, !1, this.eAccess)
}
,
HUYA.LiveAppUAEx = function() {
    this.sIMEI = "",
    this.sAPN = "",
    this.sNetType = ""
}
,
HUYA.LiveAppUAEx.prototype._clone = function() {
    return new HUYA.LiveAppUAEx
}
,
HUYA.LiveAppUAEx.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.LiveAppUAEx.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.LiveAppUAEx.prototype.writeTo = function(t) {
    t.writeString(1, this.sIMEI),
    t.writeString(2, this.sAPN),
    t.writeString(3, this.sNetType)
}
,
HUYA.LiveAppUAEx.prototype.readFrom = function(t) {
    this.sIMEI = t.readString(1, !1, this.sIMEI),
    this.sAPN = t.readString(2, !1, this.sAPN),
    this.sNetType = t.readString(3, !1, this.sNetType)
}
,
HUYA.LiveUserbase = function() {
    this.eSource = 0,
    this.eType = 0,
    this.tUAEx = new HUYA.LiveAppUAEx
}
,
HUYA.LiveUserbase.prototype._clone = function() {
    return new HUYA.LiveUserbase
}
,
HUYA.LiveUserbase.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.LiveUserbase.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.LiveUserbase.prototype.writeTo = function(t) {
    t.writeInt32(0, this.eSource),
    t.writeInt32(1, this.eType),
    t.writeStruct(2, this.tUAEx)
}
,
HUYA.LiveUserbase.prototype.readFrom = function(t) {
    this.eSource = t.readInt32(0, !1, this.eSource),
    this.eType = t.readInt32(1, !1, this.eType),
    this.tUAEx = t.readStruct(2, !1, this.tUAEx)
}
,
HUYA.LiveProxyValue = function() {
    this.eProxyType = 0,
    this.sProxy = new Taf.Vector(new Taf.STRING)
}
,
HUYA.LiveProxyValue.prototype._clone = function() {
    return new HUYA.LiveProxyValue
}
,
HUYA.LiveProxyValue.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.LiveProxyValue.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.LiveProxyValue.prototype.writeTo = function(t) {
    t.writeInt32(0, this.eProxyType),
    t.writeVector(1, this.sProxy)
}
,
HUYA.LiveProxyValue.prototype.readFrom = function(t) {
    this.eProxyType = t.readInt32(0, !1, this.eProxyType),
    this.sProxy = t.readVector(1, !1, this.sProxy)
}
,
HUYA.SendItemSubBroadcastPacket = function() {
    this.iItemType = 0,
    this.strPayId = "",
    this.iItemCount = 0,
    this.lPresenterUid = 0,
    this.lSenderUid = 0,
    this.sPresenterNick = "",
    this.sSenderNick = "",
    this.sSendContent = "",
    this.iItemCountByGroup = 0,
    this.iItemGroup = 0,
    this.iSuperPupleLevel = 0,
    this.iComboScore = 0,
    this.iDisplayInfo = 0,
    this.iEffectType = 0,
    this.iSenderIcon = "",
    this.iPresenterIcon = "",
    this.iTemplateType = 0,
    this.sExpand = "",
    this.bBusi = !1,
    this.iColorEffectType = 0
}
,
HUYA.SendItemSubBroadcastPacket.prototype._clone = function() {
    return new HUYA.SendItemSubBroadcastPacket
}
,
HUYA.SendItemSubBroadcastPacket.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.SendItemSubBroadcastPacket.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.SendItemSubBroadcastPacket.prototype.writeTo = function(t) {
    t.writeInt32(0, this.iItemType),
    t.writeString(1, this.strPayId),
    t.writeInt32(2, this.iItemCount),
    t.writeInt64(3, this.lPresenterUid),
    t.writeInt64(4, this.lSenderUid),
    t.writeString(5, this.sPresenterNick),
    t.writeString(6, this.sSenderNick),
    t.writeString(7, this.sSendContent),
    t.writeInt32(8, this.iItemCountByGroup),
    t.writeInt32(9, this.iItemGroup),
    t.writeInt32(10, this.iSuperPupleLevel),
    t.writeInt32(11, this.iComboScore),
    t.writeInt32(12, this.iDisplayInfo),
    t.writeInt32(13, this.iEffectType),
    t.writeString(14, this.iSenderIcon),
    t.writeString(15, this.iPresenterIcon),
    t.writeInt32(16, this.iTemplateType),
    t.writeString(17, this.sExpand),
    t.writeBoolean(18, this.bBusi),
    t.writeInt32(19, this.iColorEffectType)
}
,
HUYA.SendItemSubBroadcastPacket.prototype.readFrom = function(t) {
    this.iItemType = t.readInt32(0, !1, this.iItemType),
    this.strPayId = t.readString(1, !1, this.strPayId),
    this.iItemCount = t.readInt32(2, !1, this.iItemCount),
    this.lPresenterUid = t.readInt64(3, !1, this.lPresenterUid),
    this.lSenderUid = t.readInt64(4, !1, this.lSenderUid),
    this.sPresenterNick = t.readString(5, !1, this.sPresenterNick),
    this.sSenderNick = t.readString(6, !1, this.sSenderNick),
    this.sSendContent = t.readString(7, !1, this.sSendContent),
    this.iItemCountByGroup = t.readInt32(8, !1, this.iItemCountByGroup),
    this.iItemGroup = t.readInt32(9, !1, this.iItemGroup),
    this.iSuperPupleLevel = t.readInt32(10, !1, this.iSuperPupleLevel),
    this.iComboScore = t.readInt32(11, !1, this.iComboScore),
    this.iDisplayInfo = t.readInt32(12, !1, this.iDisplayInfo),
    this.iEffectType = t.readInt32(13, !1, this.iEffectType),
    this.iSenderIcon = t.readString(14, !1, this.iSenderIcon),
    this.iPresenterIcon = t.readString(15, !1, this.iPresenterIcon),
    this.iTemplateType = t.readInt32(16, !1, this.iTemplateType),
    this.sExpand = t.readString(17, !1, this.sExpand),
    this.bBusi = t.readBoolean(18, !1, this.bBusi),
    this.iColorEffectType = t.readInt32(19, !1, this.iColorEffectType)
}
,
HUYA.SendItemNoticeWordBroadcastPacket = function() {
    this.iItemType = 0,
    this.iItemCount = 0,
    this.lSenderSid = 0,
    this.lSenderUid = 0,
    this.sSenderNick = "",
    this.lPresenterUid = 0,
    this.sPresenterNick = "",
    this.lNoticeChannelCount = 0,
    this.iItemCountByGroup = 0,
    this.iItemGroup = 0,
    this.iDisplayInfo = 0,
    this.iSuperPupleLevel = 0,
    this.iTemplateType = 0,
    this.sExpand = "",
    this.bBusi = !1
}
,
HUYA.SendItemNoticeWordBroadcastPacket.prototype._clone = function() {
    return new HUYA.SendItemNoticeWordBroadcastPacket
}
,
HUYA.SendItemNoticeWordBroadcastPacket.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.SendItemNoticeWordBroadcastPacket.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.SendItemNoticeWordBroadcastPacket.prototype.writeTo = function(t) {
    t.writeInt32(0, this.iItemType),
    t.writeInt32(1, this.iItemCount),
    t.writeInt64(2, this.lSenderSid),
    t.writeInt64(3, this.lSenderUid),
    t.writeString(4, this.sSenderNick),
    t.writeInt64(5, this.lPresenterUid),
    t.writeString(6, this.sPresenterNick),
    t.writeInt64(7, this.lNoticeChannelCount),
    t.writeInt32(8, this.iItemCountByGroup),
    t.writeInt32(9, this.iItemGroup),
    t.writeInt32(10, this.iDisplayInfo),
    t.writeInt32(11, this.iSuperPupleLevel),
    t.writeInt32(12, this.iTemplateType),
    t.writeString(13, this.sExpand),
    t.writeBoolean(14, this.bBusi)
}
,
HUYA.SendItemNoticeWordBroadcastPacket.prototype.readFrom = function(t) {
    this.iItemType = t.readInt32(0, !1, this.iItemType),
    this.iItemCount = t.readInt32(1, !1, this.iItemCount),
    this.lSenderSid = t.readInt64(2, !1, this.lSenderSid),
    this.lSenderUid = t.readInt64(3, !1, this.lSenderUid),
    this.sSenderNick = t.readString(4, !1, this.sSenderNick),
    this.lPresenterUid = t.readInt64(5, !1, this.lPresenterUid),
    this.sPresenterNick = t.readString(6, !1, this.sPresenterNick),
    this.lNoticeChannelCount = t.readInt64(7, !1, this.lNoticeChannelCount),
    this.iItemCountByGroup = t.readInt32(8, !1, this.iItemCountByGroup),
    this.iItemGroup = t.readInt32(9, !1, this.iItemGroup),
    this.iDisplayInfo = t.readInt32(10, !1, this.iDisplayInfo),
    this.iSuperPupleLevel = t.readInt32(11, !1, this.iSuperPupleLevel),
    this.iTemplateType = t.readInt32(12, !1, this.iTemplateType),
    this.sExpand = t.readString(13, !1, this.sExpand),
    this.bBusi = t.readBoolean(14, !1, this.bBusi)
}
,
HUYA.BeginLiveNotice = function() {
    this.lPresenterUid = 0,
    this.iGameId = 0,
    this.sGameName = "",
    this.iRandomRange = 0,
    this.iStreamType = 0,
    this.vStreamInfo = new Taf.Vector(new HUYA.StreamInfo),
    this.vCdnList = new Taf.Vector(new Taf.STRING),
    this.lLiveId = 0,
    this.iPCDefaultBitRate = 0,
    this.iWebDefaultBitRate = 0,
    this.iMobileDefaultBitRate = 0,
    this.lMultiStreamFlag = 0,
    this.sNick = "",
    this.lYYId = 0,
    this.lAttendeeCount = 0,
    this.iCodecType = 0,
    this.iScreenType = 0,
    this.vMultiStreamInfo = new Taf.Vector(new HUYA.MultiStreamInfo),
    this.sLiveDesc = "",
    this.lLiveCompatibleFlag = 0,
    this.sAvatarUrl = "",
    this.iSourceType = 0,
    this.sSubchannelName = "",
    this.sVideoCaptureUrl = "",
    this.iStartTime = 0,
    this.lChannelId = 0,
    this.lSubChannelId = 0,
    this.sLocation = ""
}
,
HUYA.BeginLiveNotice.prototype._clone = function() {
    return new HUYA.BeginLiveNotice
}
,
HUYA.BeginLiveNotice.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.BeginLiveNotice.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.BeginLiveNotice.prototype.writeTo = function(t) {
    t.writeInt64(0, this.lPresenterUid),
    t.writeInt32(1, this.iGameId),
    t.writeString(2, this.sGameName),
    t.writeInt32(3, this.iRandomRange),
    t.writeInt32(4, this.iStreamType),
    t.writeVector(5, this.vStreamInfo),
    t.writeVector(6, this.vCdnList),
    t.writeInt64(7, this.lLiveId),
    t.writeInt32(8, this.iPCDefaultBitRate),
    t.writeInt32(9, this.iWebDefaultBitRate),
    t.writeInt32(10, this.iMobileDefaultBitRate),
    t.writeInt64(11, this.lMultiStreamFlag),
    t.writeString(12, this.sNick),
    t.writeInt64(13, this.lYYId),
    t.writeInt64(14, this.lAttendeeCount),
    t.writeInt32(15, this.iCodecType),
    t.writeInt32(16, this.iScreenType),
    t.writeVector(17, this.vMultiStreamInfo),
    t.writeString(18, this.sLiveDesc),
    t.writeInt64(19, this.lLiveCompatibleFlag),
    t.writeString(20, this.sAvatarUrl),
    t.writeInt32(21, this.iSourceType),
    t.writeString(22, this.sSubchannelName),
    t.writeString(23, this.sVideoCaptureUrl),
    t.writeInt32(24, this.iStartTime),
    t.writeInt64(25, this.lChannelId),
    t.writeInt64(26, this.lSubChannelId),
    t.writeString(27, this.sLocation)
}
,
HUYA.BeginLiveNotice.prototype.readFrom = function(t) {
    this.lPresenterUid = t.readInt64(0, !1, this.lPresenterUid),
    this.iGameId = t.readInt32(1, !1, this.iGameId),
    this.sGameName = t.readString(2, !1, this.sGameName),
    this.iRandomRange = t.readInt32(3, !1, this.iRandomRange),
    this.iStreamType = t.readInt32(4, !1, this.iStreamType),
    this.vStreamInfo = t.readVector(5, !1, this.vStreamInfo),
    this.vCdnList = t.readVector(6, !1, this.vCdnList),
    this.lLiveId = t.readInt64(7, !1, this.lLiveId),
    this.iPCDefaultBitRate = t.readInt32(8, !1, this.iPCDefaultBitRate),
    this.iWebDefaultBitRate = t.readInt32(9, !1, this.iWebDefaultBitRate),
    this.iMobileDefaultBitRate = t.readInt32(10, !1, this.iMobileDefaultBitRate),
    this.lMultiStreamFlag = t.readInt64(11, !1, this.lMultiStreamFlag),
    this.sNick = t.readString(12, !1, this.sNick),
    this.lYYId = t.readInt64(13, !1, this.lYYId),
    this.lAttendeeCount = t.readInt64(14, !1, this.lAttendeeCount),
    this.iCodecType = t.readInt32(15, !1, this.iCodecType),
    this.iScreenType = t.readInt32(16, !1, this.iScreenType),
    this.vMultiStreamInfo = t.readVector(17, !1, this.vMultiStreamInfo),
    this.sLiveDesc = t.readString(18, !1, this.sLiveDesc),
    this.lLiveCompatibleFlag = t.readInt64(19, !1, this.lLiveCompatibleFlag),
    this.sAvatarUrl = t.readString(20, !1, this.sAvatarUrl),
    this.iSourceType = t.readInt32(21, !1, this.iSourceType),
    this.sSubchannelName = t.readString(22, !1, this.sSubchannelName),
    this.sVideoCaptureUrl = t.readString(23, !1, this.sVideoCaptureUrl),
    this.iStartTime = t.readInt32(24, !1, this.iStartTime),
    this.lChannelId = t.readInt64(25, !1, this.lChannelId),
    this.lSubChannelId = t.readInt64(26, !1, this.lSubChannelId),
    this.sLocation = t.readString(27, !1, this.sLocation)
}
,
HUYA.EndLiveNotice = function() {
    this.lPresenterUid = 0,
    this.iReason = 0,
    this.lLiveId = 0
}
,
HUYA.EndLiveNotice.prototype._clone = function() {
    return new HUYA.EndLiveNotice
}
,
HUYA.EndLiveNotice.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.EndLiveNotice.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.EndLiveNotice.prototype.writeTo = function(t) {
    t.writeInt64(0, this.lPresenterUid),
    t.writeInt32(1, this.iReason),
    t.writeInt64(2, this.lLiveId)
}
,
HUYA.EndLiveNotice.prototype.readFrom = function(t) {
    this.lPresenterUid = t.readInt64(0, !1, this.lPresenterUid),
    this.iReason = t.readInt32(1, !1, this.iReason),
    this.lLiveId = t.readInt64(2, !1, this.lLiveId)
}
,
HUYA.GetPropsListReq = function() {
    this.tUserId = new HUYA.UserId,
    this.sMd5 = "",
    this.iTemplateType = 64,
    this.sVersion = "",
    this.iAppId = 0,
    this.lPresenterUid = 0,
    this.lSid = 0,
    this.lSubSid = 0,
    this.iGameId = 0
}
,
HUYA.GetPropsListReq.prototype._clone = function() {
    return new HUYA.GetPropsListReq
}
,
HUYA.GetPropsListReq.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.GetPropsListReq.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.GetPropsListReq.prototype.writeTo = function(t) {
    t.writeStruct(1, this.tUserId),
    t.writeString(2, this.sMd5),
    t.writeInt32(3, this.iTemplateType),
    t.writeString(4, this.sVersion),
    t.writeInt32(5, this.iAppId),
    t.writeInt64(6, this.lPresenterUid),
    t.writeInt64(7, this.lSid),
    t.writeInt64(8, this.lSubSid),
    t.writeInt32(9, this.iGameId)
}
,
HUYA.GetPropsListReq.prototype.readFrom = function(t) {
    this.tUserId = t.readStruct(1, !1, this.tUserId),
    this.sMd5 = t.readString(2, !1, this.sMd5),
    this.iTemplateType = t.readInt32(3, !1, this.iTemplateType),
    this.sVersion = t.readString(4, !1, this.sVersion),
    this.iAppId = t.readInt32(5, !1, this.iAppId),
    this.lPresenterUid = t.readInt64(6, !1, this.lPresenterUid),
    this.lSid = t.readInt64(7, !1, this.lSid),
    this.lSubSid = t.readInt64(8, !1, this.lSubSid),
    this.iGameId = t.readInt32(9, !1, this.iGameId)
}
,
HUYA.GetPropsListRsp = function() {
    this.vPropsItemList = new Taf.Vector(new HUYA.PropsItem),
    this.sMd5 = "",
    this.iNewEffectSwitch = 0,
    this.iMirrorRoomShowNum = 0,
    this.iGameRoomShowNum = 0
}
,
HUYA.GetPropsListRsp.prototype._clone = function() {
    return new HUYA.GetPropsListRsp
}
,
HUYA.GetPropsListRsp.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.GetPropsListRsp.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.GetPropsListRsp.prototype.writeTo = function(t) {
    t.writeVector(1, this.vPropsItemList),
    t.writeString(2, this.sMd5),
    t.writeInt16(3, this.iNewEffectSwitch),
    t.writeInt16(4, this.iMirrorRoomShowNum),
    t.writeInt16(5, this.iGameRoomShowNum)
}
,
HUYA.GetPropsListRsp.prototype.readFrom = function(t) {
    this.vPropsItemList = t.readVector(1, !1, this.vPropsItemList),
    this.sMd5 = t.readString(2, !1, this.sMd5),
    this.iNewEffectSwitch = t.readInt16(3, !1, this.iNewEffectSwitch),
    this.iMirrorRoomShowNum = t.readInt16(4, !1, this.iMirrorRoomShowNum),
    this.iGameRoomShowNum = t.readInt16(5, !1, this.iGameRoomShowNum)
}
,
HUYA.PropsItem = function() {
    this.iPropsId = 0,
    this.sPropsName = "",
    this.iPropsYb = 0,
    this.iPropsGreenBean = 0,
    this.iPropsWhiteBean = 0,
    this.iPropsGoldenBean = 0,
    this.iPropsRed = 0,
    this.iPropsPopular = 0,
    this.iPropsExpendNum = -1,
    this.iPropsFansValue = -1,
    this.vPropsNum = new Taf.Vector(new Taf.INT32),
    this.iPropsMaxNum = 0,
    this.iPropsBatterFlag = 0,
    this.vPropsChannel = new Taf.Vector(new Taf.INT32),
    this.sPropsToolTip = "",
    this.vPropsIdentity = new Taf.Vector(new HUYA.PropsIdentity),
    this.iPropsWeights = 0,
    this.iPropsLevel = 0,
    this.tDisplayInfo = new HUYA.DisplayInfo,
    this.tSpecialInfo = new HUYA.SpecialInfo,
    this.iPropsGrade = 0,
    this.iPropsGroupNum = 0,
    this.sPropsCommBannerResource = "",
    this.sPropsOwnBannerResource = "",
    this.iPropsShowFlag = 0,
    this.iTemplateType = 0,
    this.iShelfStatus = 0,
    this.sAndroidLogo = "",
    this.sIpadLogo = "",
    this.sIphoneLogo = "",
    this.sPropsCommBannerResourceEx = "",
    this.sPropsOwnBannerResourceEx = "",
    this.vPresenterUid = new Taf.Vector(new Taf.INT64),
    this.vPropView = new Taf.Vector(new HUYA.PropView),
    this.iFaceUSwitch = 0,
    this.iDisplayCd = 0,
    this.iCount = 0,
    this.iVbCount = 0,
    this.vWebPropsNum = new Taf.Vector(new Taf.STRING)
}
,
HUYA.PropsItem.prototype._clone = function() {
    return new HUYA.PropsItem
}
,
HUYA.PropsItem.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.PropsItem.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.PropsItem.prototype.writeTo = function(t) {
    t.writeInt32(1, this.iPropsId),
    t.writeString(2, this.sPropsName),
    t.writeInt32(3, this.iPropsYb),
    t.writeInt32(4, this.iPropsGreenBean),
    t.writeInt32(5, this.iPropsWhiteBean),
    t.writeInt32(6, this.iPropsGoldenBean),
    t.writeInt32(7, this.iPropsRed),
    t.writeInt32(8, this.iPropsPopular),
    t.writeInt32(9, this.iPropsExpendNum),
    t.writeInt32(10, this.iPropsFansValue),
    t.writeVector(11, this.vPropsNum),
    t.writeInt32(12, this.iPropsMaxNum),
    t.writeInt32(13, this.iPropsBatterFlag),
    t.writeVector(14, this.vPropsChannel),
    t.writeString(15, this.sPropsToolTip),
    t.writeVector(16, this.vPropsIdentity),
    t.writeInt32(17, this.iPropsWeights),
    t.writeInt32(18, this.iPropsLevel),
    t.writeStruct(19, this.tDisplayInfo),
    t.writeStruct(20, this.tSpecialInfo),
    t.writeInt32(21, this.iPropsGrade),
    t.writeInt32(22, this.iPropsGroupNum),
    t.writeString(23, this.sPropsCommBannerResource),
    t.writeString(24, this.sPropsOwnBannerResource),
    t.writeInt32(25, this.iPropsShowFlag),
    t.writeInt32(26, this.iTemplateType),
    t.writeInt32(27, this.iShelfStatus),
    t.writeString(28, this.sAndroidLogo),
    t.writeString(29, this.sIpadLogo),
    t.writeString(30, this.sIphoneLogo),
    t.writeString(31, this.sPropsCommBannerResourceEx),
    t.writeString(32, this.sPropsOwnBannerResourceEx),
    t.writeVector(33, this.vPresenterUid),
    t.writeVector(34, this.vPropView),
    t.writeInt16(35, this.iFaceUSwitch),
    t.writeInt16(36, this.iDisplayCd),
    t.writeInt16(37, this.iCount),
    t.writeInt32(38, this.iVbCount),
    t.writeVector(39, this.vWebPropsNum)
}
,
HUYA.PropsItem.prototype.readFrom = function(t) {
    this.iPropsId = t.readInt32(1, !1, this.iPropsId),
    this.sPropsName = t.readString(2, !1, this.sPropsName),
    this.iPropsYb = t.readInt32(3, !1, this.iPropsYb),
    this.iPropsGreenBean = t.readInt32(4, !1, this.iPropsGreenBean),
    this.iPropsWhiteBean = t.readInt32(5, !1, this.iPropsWhiteBean),
    this.iPropsGoldenBean = t.readInt32(6, !1, this.iPropsGoldenBean),
    this.iPropsRed = t.readInt32(7, !1, this.iPropsRed),
    this.iPropsPopular = t.readInt32(8, !1, this.iPropsPopular),
    this.iPropsExpendNum = t.readInt32(9, !1, this.iPropsExpendNum),
    this.iPropsFansValue = t.readInt32(10, !1, this.iPropsFansValue),
    this.vPropsNum = t.readVector(11, !1, this.vPropsNum),
    this.iPropsMaxNum = t.readInt32(12, !1, this.iPropsMaxNum),
    this.iPropsBatterFlag = t.readInt32(13, !1, this.iPropsBatterFlag),
    this.vPropsChannel = t.readVector(14, !1, this.vPropsChannel),
    this.sPropsToolTip = t.readString(15, !1, this.sPropsToolTip),
    this.vPropsIdentity = t.readVector(16, !1, this.vPropsIdentity),
    this.iPropsWeights = t.readInt32(17, !1, this.iPropsWeights),
    this.iPropsLevel = t.readInt32(18, !1, this.iPropsLevel),
    this.tDisplayInfo = t.readStruct(19, !1, this.tDisplayInfo),
    this.tSpecialInfo = t.readStruct(20, !1, this.tSpecialInfo),
    this.iPropsGrade = t.readInt32(21, !1, this.iPropsGrade),
    this.iPropsGroupNum = t.readInt32(22, !1, this.iPropsGroupNum),
    this.sPropsCommBannerResource = t.readString(23, !1, this.sPropsCommBannerResource),
    this.sPropsOwnBannerResource = t.readString(24, !1, this.sPropsOwnBannerResource),
    this.iPropsShowFlag = t.readInt32(25, !1, this.iPropsShowFlag),
    this.iTemplateType = t.readInt32(26, !1, this.iTemplateType),
    this.iShelfStatus = t.readInt32(27, !1, this.iShelfStatus),
    this.sAndroidLogo = t.readString(28, !1, this.sAndroidLogo),
    this.sIpadLogo = t.readString(29, !1, this.sIpadLogo),
    this.sIphoneLogo = t.readString(30, !1, this.sIphoneLogo),
    this.sPropsCommBannerResourceEx = t.readString(31, !1, this.sPropsCommBannerResourceEx),
    this.sPropsOwnBannerResourceEx = t.readString(32, !1, this.sPropsOwnBannerResourceEx),
    this.vPresenterUid = t.readVector(33, !1, this.vPresenterUid),
    this.vPropView = t.readVector(34, !1, this.vPropView),
    this.iFaceUSwitch = t.readInt16(35, !1, this.iFaceUSwitch),
    this.iDisplayCd = t.readInt16(36, !1, this.iDisplayCd),
    this.iCount = t.readInt16(37, !1, this.iCount),
    this.iVbCount = t.readInt32(38, !1, this.iVbCount),
    this.vWebPropsNum = t.readVector(39, !1, this.vWebPropsNum)
}
,
HUYA.PropsIdentity = function() {
    this.iPropsIdType = 0,
    this.sPropsPic18 = "",
    this.sPropsPic24 = "",
    this.sPropsPicGif = "",
    this.sPropsBannerResource = "",
    this.sPropsBannerSize = "",
    this.sPropsBannerMaxTime = "",
    this.sPropsChatBannerResource = "",
    this.sPropsChatBannerSize = "",
    this.sPropsChatBannerMaxTime = "",
    this.iPropsChatBannerPos = 0,
    this.iPropsChatBannerIsCombo = 0,
    this.sPropsRollContent = "",
    this.iPropsBannerAnimationstyle = 0,
    this.sPropFaceu = "",
    this.sPropH5Resource = "",
    this.sPropsWeb = "",
    this.sWitch = 0,
    this.sCornerMark = "",
    this.iPropViewId = 0,
    this.sPropStreamerResource = "",
    this.iStreamerFrameRate = 0,
    this.sPropsPic108 = "",
    this.sPcBannerResource = ""
}
,
HUYA.PropsIdentity.prototype._clone = function() {
    return new HUYA.PropsIdentity
}
,
HUYA.PropsIdentity.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.PropsIdentity.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.PropsIdentity.prototype.writeTo = function(t) {
    t.writeInt32(1, this.iPropsIdType),
    t.writeString(2, this.sPropsPic18),
    t.writeString(3, this.sPropsPic24),
    t.writeString(4, this.sPropsPicGif),
    t.writeString(5, this.sPropsBannerResource),
    t.writeString(6, this.sPropsBannerSize),
    t.writeString(7, this.sPropsBannerMaxTime),
    t.writeString(8, this.sPropsChatBannerResource),
    t.writeString(9, this.sPropsChatBannerSize),
    t.writeString(10, this.sPropsChatBannerMaxTime),
    t.writeInt32(11, this.iPropsChatBannerPos),
    t.writeInt32(12, this.iPropsChatBannerIsCombo),
    t.writeString(13, this.sPropsRollContent),
    t.writeInt32(14, this.iPropsBannerAnimationstyle),
    t.writeString(15, this.sPropFaceu),
    t.writeString(16, this.sPropH5Resource),
    t.writeString(17, this.sPropsWeb),
    t.writeInt32(18, this.sWitch),
    t.writeString(19, this.sCornerMark),
    t.writeInt32(20, this.iPropViewId),
    t.writeString(21, this.sPropStreamerResource),
    t.writeInt16(22, this.iStreamerFrameRate),
    t.writeString(23, this.sPropsPic108),
    t.writeString(24, this.sPcBannerResource)
}
,
HUYA.PropsIdentity.prototype.readFrom = function(t) {
    this.iPropsIdType = t.readInt32(1, !1, this.iPropsIdType),
    this.sPropsPic18 = t.readString(2, !1, this.sPropsPic18),
    this.sPropsPic24 = t.readString(3, !1, this.sPropsPic24),
    this.sPropsPicGif = t.readString(4, !1, this.sPropsPicGif),
    this.sPropsBannerResource = t.readString(5, !1, this.sPropsBannerResource),
    this.sPropsBannerSize = t.readString(6, !1, this.sPropsBannerSize),
    this.sPropsBannerMaxTime = t.readString(7, !1, this.sPropsBannerMaxTime),
    this.sPropsChatBannerResource = t.readString(8, !1, this.sPropsChatBannerResource),
    this.sPropsChatBannerSize = t.readString(9, !1, this.sPropsChatBannerSize),
    this.sPropsChatBannerMaxTime = t.readString(10, !1, this.sPropsChatBannerMaxTime),
    this.iPropsChatBannerPos = t.readInt32(11, !1, this.iPropsChatBannerPos),
    this.iPropsChatBannerIsCombo = t.readInt32(12, !1, this.iPropsChatBannerIsCombo),
    this.sPropsRollContent = t.readString(13, !1, this.sPropsRollContent),
    this.iPropsBannerAnimationstyle = t.readInt32(14, !1, this.iPropsBannerAnimationstyle),
    this.sPropFaceu = t.readString(15, !1, this.sPropFaceu),
    this.sPropH5Resource = t.readString(16, !1, this.sPropH5Resource),
    this.sPropsWeb = t.readString(17, !1, this.sPropsWeb),
    this.sWitch = t.readInt32(18, !1, this.sWitch),
    this.sCornerMark = t.readString(19, !1, this.sCornerMark),
    this.iPropViewId = t.readInt32(20, !1, this.iPropViewId),
    this.sPropStreamerResource = t.readString(21, !1, this.sPropStreamerResource),
    this.iStreamerFrameRate = t.readInt16(22, !1, this.iStreamerFrameRate),
    this.sPropsPic108 = t.readString(23, !1, this.sPropsPic108),
    this.sPcBannerResource = t.readString(24, !1, this.sPcBannerResource)
}
,
HUYA.PropView = function() {
    this.id = 0,
    this.name = "",
    this.uids = new Taf.Map(new Taf.INT64,new Taf.INT16),
    this.tips = ""
}
,
HUYA.PropView.prototype._clone = function() {
    return new HUYA.PropView
}
,
HUYA.PropView.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.PropView.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.PropView.prototype.writeTo = function(t) {
    t.writeInt32(0, this.id),
    t.writeString(1, this.name),
    t.writeMap(2, this.uids),
    t.writeString(3, this.tips)
}
,
HUYA.PropView.prototype.readFrom = function(t) {
    this.id = t.readInt32(0, !1, this.id),
    this.name = t.readString(1, !1, this.name),
    this.uids = t.readMap(2, !1, this.uids),
    this.tips = t.readString(3, !1, this.tips)
}
,
HUYA.DisplayInfo = function() {
    this.iMarqueeScopeMin = 0,
    this.iMarqueeScopeMax = 0,
    this.iCurrentVideoNum = 0,
    this.iCurrentVideoMin = 0,
    this.iCurrentVideoMax = 0,
    this.iAllVideoNum = 0,
    this.iAllVideoMin = 0,
    this.iAllVideoMax = 0,
    this.iCurrentScreenNum = 0,
    this.iCurrentScreenMin = 0,
    this.iCurrentScreenMax = 0
}
,
HUYA.DisplayInfo.prototype._clone = function() {
    return new HUYA.DisplayInfo
}
,
HUYA.DisplayInfo.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.DisplayInfo.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.DisplayInfo.prototype.writeTo = function(t) {
    t.writeInt32(1, this.iMarqueeScopeMin),
    t.writeInt32(2, this.iMarqueeScopeMax),
    t.writeInt32(3, this.iCurrentVideoNum),
    t.writeInt32(4, this.iCurrentVideoMin),
    t.writeInt32(5, this.iCurrentVideoMax),
    t.writeInt32(6, this.iAllVideoNum),
    t.writeInt32(7, this.iAllVideoMin),
    t.writeInt32(8, this.iAllVideoMax),
    t.writeInt32(9, this.iCurrentScreenNum),
    t.writeInt32(10, this.iCurrentScreenMin),
    t.writeInt32(11, this.iCurrentScreenMax)
}
,
HUYA.DisplayInfo.prototype.readFrom = function(t) {
    this.iMarqueeScopeMin = t.readInt32(1, !1, this.iMarqueeScopeMin),
    this.iMarqueeScopeMax = t.readInt32(2, !1, this.iMarqueeScopeMax),
    this.iCurrentVideoNum = t.readInt32(3, !1, this.iCurrentVideoNum),
    this.iCurrentVideoMin = t.readInt32(4, !1, this.iCurrentVideoMin),
    this.iCurrentVideoMax = t.readInt32(5, !1, this.iCurrentVideoMax),
    this.iAllVideoNum = t.readInt32(6, !1, this.iAllVideoNum),
    this.iAllVideoMin = t.readInt32(7, !1, this.iAllVideoMin),
    this.iAllVideoMax = t.readInt32(8, !1, this.iAllVideoMax),
    this.iCurrentScreenNum = t.readInt32(9, !1, this.iCurrentScreenNum),
    this.iCurrentScreenMin = t.readInt32(10, !1, this.iCurrentScreenMin),
    this.iCurrentScreenMax = t.readInt32(11, !1, this.iCurrentScreenMax)
}
,
HUYA.SpecialInfo = function() {
    this.iFirstSingle = 0,
    this.iFirstGroup = 0,
    this.sFirstTips = "",
    this.iSecondSingle = 0,
    this.iSecondGroup = 0,
    this.sSecondTips = "",
    this.iThirdSingle = 0,
    this.iThirdGroup = 0,
    this.sThirdTips = "",
    this.iWorldSingle = 0,
    this.iWorldGroup = 0
}
,
HUYA.SpecialInfo.prototype._clone = function() {
    return new HUYA.SpecialInfo
}
,
HUYA.SpecialInfo.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.SpecialInfo.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.SpecialInfo.prototype.writeTo = function(t) {
    t.writeInt32(1, this.iFirstSingle),
    t.writeInt32(2, this.iFirstGroup),
    t.writeString(3, this.sFirstTips),
    t.writeInt32(4, this.iSecondSingle),
    t.writeInt32(5, this.iSecondGroup),
    t.writeString(6, this.sSecondTips),
    t.writeInt32(7, this.iThirdSingle),
    t.writeInt32(8, this.iThirdGroup),
    t.writeString(9, this.sThirdTips),
    t.writeInt32(10, this.iWorldSingle),
    t.writeInt32(11, this.iWorldGroup)
}
,
HUYA.SpecialInfo.prototype.readFrom = function(t) {
    this.iFirstSingle = t.readInt32(1, !1, this.iFirstSingle),
    this.iFirstGroup = t.readInt32(2, !1, this.iFirstGroup),
    this.sFirstTips = t.readString(3, !1, this.sFirstTips),
    this.iSecondSingle = t.readInt32(4, !1, this.iSecondSingle),
    this.iSecondGroup = t.readInt32(5, !1, this.iSecondGroup),
    this.sSecondTips = t.readString(6, !1, this.sSecondTips),
    this.iThirdSingle = t.readInt32(7, !1, this.iThirdSingle),
    this.iThirdGroup = t.readInt32(8, !1, this.iThirdGroup),
    this.sThirdTips = t.readString(9, !1, this.sThirdTips),
    this.iWorldSingle = t.readInt32(10, !1, this.iWorldSingle),
    this.iWorldGroup = t.readInt32(11, !1, this.iWorldGroup)
}
,
HUYA.AttendeeCountNotice = function() {
    this.iAttendeeCount = 0
}
,
HUYA.AttendeeCountNotice.prototype._clone = function() {
    return new HUYA.AttendeeCountNotice
}
,
HUYA.AttendeeCountNotice.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.AttendeeCountNotice.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.AttendeeCountNotice.prototype.writeTo = function(t) {
    t.writeInt32(0, this.iAttendeeCount)
}
,
HUYA.AttendeeCountNotice.prototype.readFrom = function(t) {
    this.iAttendeeCount = t.readInt32(0, !1, this.iAttendeeCount)
}
,
HUYA.BulletFormat = function() {
    this.iFontColor = -1,
    this.iFontSize = 4,
    this.iTextSpeed = 0,
    this.iTransitionType = 1,
    this.iPopupStyle = 0
}
,
HUYA.BulletFormat.prototype._clone = function() {
    return new HUYA.BulletFormat
}
,
HUYA.BulletFormat.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.BulletFormat.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.BulletFormat.prototype.writeTo = function(t) {
    t.writeInt32(0, this.iFontColor),
    t.writeInt32(1, this.iFontSize),
    t.writeInt32(2, this.iTextSpeed),
    t.writeInt32(3, this.iTransitionType),
    t.writeInt32(4, this.iPopupStyle)
}
,
HUYA.BulletFormat.prototype.readFrom = function(t) {
    this.iFontColor = t.readInt32(0, !1, this.iFontColor),
    this.iFontSize = t.readInt32(1, !1, this.iFontSize),
    this.iTextSpeed = t.readInt32(2, !1, this.iTextSpeed),
    this.iTransitionType = t.readInt32(3, !1, this.iTransitionType),
    this.iPopupStyle = t.readInt32(4, !1, this.iPopupStyle)
}
,
HUYA.ContentFormat = function() {
    this.iFontColor = -1,
    this.iFontSize = 4,
    this.iPopupStyle = 0
}
,
HUYA.ContentFormat.prototype._clone = function() {
    return new HUYA.ContentFormat
}
,
HUYA.ContentFormat.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.ContentFormat.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.ContentFormat.prototype.writeTo = function(t) {
    t.writeInt32(0, this.iFontColor),
    t.writeInt32(1, this.iFontSize),
    t.writeInt32(2, this.iPopupStyle)
}
,
HUYA.ContentFormat.prototype.readFrom = function(t) {
    this.iFontColor = t.readInt32(0, !1, this.iFontColor),
    this.iFontSize = t.readInt32(1, !1, this.iFontSize),
    this.iPopupStyle = t.readInt32(2, !1, this.iPopupStyle)
}
,
HUYA.DecorationInfo = function() {
    this.iAppId = 0,
    this.iViewType = 0,
    this.vData = new Taf.BinBuffer
}
,
HUYA.DecorationInfo.prototype._clone = function() {
    return new HUYA.DecorationInfo
}
,
HUYA.DecorationInfo.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.DecorationInfo.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.DecorationInfo.prototype.writeTo = function(t) {
    t.writeInt32(0, this.iAppId),
    t.writeInt32(1, this.iViewType),
    t.writeBytes(2, this.vData)
}
,
HUYA.DecorationInfo.prototype.readFrom = function(t) {
    this.iAppId = t.readInt32(0, !1, this.iAppId),
    this.iViewType = t.readInt32(1, !1, this.iViewType),
    this.vData = t.readBytes(2, !1, this.vData)
}
,
HUYA.SenderInfo = function() {
    this.lUid = 0,
    this.lImid = 0,
    this.sNickName = "",
    this.iGender = 0
}
,
HUYA.SenderInfo.prototype._clone = function() {
    return new HUYA.SenderInfo
}
,
HUYA.SenderInfo.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.SenderInfo.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.SenderInfo.prototype.writeTo = function(t) {
    t.writeInt64(0, this.lUid),
    t.writeInt64(1, this.lImid),
    t.writeString(2, this.sNickName),
    t.writeInt32(3, this.iGender)
}
,
HUYA.SenderInfo.prototype.readFrom = function(t) {
    this.lUid = t.readInt64(0, !1, this.lUid),
    this.lImid = t.readInt64(1, !1, this.lImid),
    this.sNickName = t.readString(2, !1, this.sNickName),
    this.iGender = t.readInt32(3, !1, this.iGender)
}
,
HUYA.UidNickName = function() {
    this.lUid = 0,
    this.sNickName = ""
}
,
HUYA.UidNickName.prototype._clone = function() {
    return new HUYA.UidNickName
}
,
HUYA.UidNickName.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.UidNickName.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.UidNickName.prototype.writeTo = function(t) {
    t.writeInt64(0, this.lUid),
    t.writeString(1, this.sNickName)
}
,
HUYA.UidNickName.prototype.readFrom = function(t) {
    this.lUid = t.readInt64(0, !1, this.lUid),
    this.sNickName = t.readString(1, !1, this.sNickName)
}
,
HUYA.MessageNotice = function() {
    this.tUserInfo = new HUYA.SenderInfo,
    this.lTid = 0,
    this.lSid = 0,
    this.sContent = "",
    this.iShowMode = 0,
    this.tFormat = new HUYA.ContentFormat,
    this.tBulletFormat = new HUYA.BulletFormat,
    this.iTermType = 0,
    this.vDecorationPrefix = new Taf.Vector(new HUYA.DecorationInfo),
    this.vDecorationSuffix = new Taf.Vector(new HUYA.DecorationInfo),
    this.vAtSomeone = new Taf.Vector(new HUYA.UidNickName),
    this.lPid = 0
}
,
HUYA.MessageNotice.prototype._clone = function() {
    return new HUYA.MessageNotice
}
,
HUYA.MessageNotice.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.MessageNotice.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.MessageNotice.prototype.writeTo = function(t) {
    t.writeStruct(0, this.tUserInfo),
    t.writeInt64(1, this.lTid),
    t.writeInt64(2, this.lSid),
    t.writeString(3, this.sContent),
    t.writeInt32(4, this.iShowMode),
    t.writeStruct(5, this.tFormat),
    t.writeStruct(6, this.tBulletFormat),
    t.writeInt32(7, this.iTermType),
    t.writeVector(8, this.vDecorationPrefix),
    t.writeVector(9, this.vDecorationSuffix),
    t.writeVector(10, this.vAtSomeone),
    t.writeInt64(11, this.lPid)
}
,
HUYA.MessageNotice.prototype.readFrom = function(t) {
    this.tUserInfo = t.readStruct(0, !1, this.tUserInfo),
    this.lTid = t.readInt64(1, !1, this.lTid),
    this.lSid = t.readInt64(2, !1, this.lSid),
    this.sContent = t.readString(3, !1, this.sContent),
    this.iShowMode = t.readInt32(4, !1, this.iShowMode),
    this.tFormat = t.readStruct(5, !1, this.tFormat),
    this.tBulletFormat = t.readStruct(6, !1, this.tBulletFormat),
    this.iTermType = t.readInt32(7, !1, this.iTermType),
    this.vDecorationPrefix = t.readVector(8, !1, this.vDecorationPrefix),
    this.vDecorationSuffix = t.readVector(9, !1, this.vDecorationSuffix),
    this.vAtSomeone = t.readVector(10, !1, this.vAtSomeone),
    this.lPid = t.readInt64(11, !1, this.lPid)
}
,
HUYA.JumpLiveEventReq = function() {
    this.tId = new HUYA.UserId,
    this.lUid = 0,
    this.lLiveId = 0,
    this.lTopCid = 0,
    this.lSubCid = 0,
    this.sFrom = "",
    this.sFromUrl = "",
    this.sNick = ""
}
,
HUYA.JumpLiveEventReq.prototype._clone = function() {
    return new HUYA.JumpLiveEventReq
}
,
HUYA.JumpLiveEventReq.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.JumpLiveEventReq.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.JumpLiveEventReq.prototype.writeTo = function(t) {
    t.writeStruct(0, this.tId),
    t.writeInt64(1, this.lUid),
    t.writeInt64(2, this.lLiveId),
    t.writeInt64(3, this.lTopCid),
    t.writeInt64(4, this.lSubCid),
    t.writeString(5, this.sFrom),
    t.writeString(6, this.sFromUrl),
    t.writeString(7, this.sNick)
}
,
HUYA.JumpLiveEventReq.prototype.readFrom = function(t) {
    this.tId = t.readStruct(0, !1, this.tId),
    this.lUid = t.readInt64(1, !1, this.lUid),
    this.lLiveId = t.readInt64(2, !1, this.lLiveId),
    this.lTopCid = t.readInt64(3, !1, this.lTopCid),
    this.lSubCid = t.readInt64(4, !1, this.lSubCid),
    this.sFrom = t.readString(5, !1, this.sFrom),
    this.sFromUrl = t.readString(6, !1, this.sFromUrl),
    this.sNick = t.readString(7, !1, this.sNick)
}
,
HUYA.EUnit = {
    EUnit_None: 0,
    EUnit_Seconds: 1,
    EUnit_Microseconds: 2,
    EUnit_Milliseconds: 3,
    EUnit_Bytes: 4,
    EUnit_Kilobytes: 5,
    EUnit_Megabytes: 6,
    EUnit_Gigabytes: 7,
    EUnit_Terabytes: 8,
    EUnit_Bits: 9,
    EUnit_Kilobits: 10,
    EUnit_Megabits: 11,
    EUnit_Gigabits: 12,
    EUnit_Terabits: 13,
    EUnit_Percent: 14,
    EUnit_Count: 15,
    EUnit_BytesPerSecond: 16,
    EUnit_KilobytesPerSecond: 17,
    EUnit_MegabytesPerSecond: 18,
    EUnit_GigabytesPerSecond: 19,
    EUnit_TerabytesPerSecond: 20,
    EUnit_BitsPerSecond: 21,
    EUnit_KilobitsPerSecond: 22,
    EUnit_MegabitsPerSecond: 23,
    EUnit_GigabitsPerSecond: 24,
    EUnit_TerabitsPerSecond: 25,
    EUnit_CountPerSecond: 26
},
HUYA.Dimension = function() {
    this.sName = "",
    this.sValue = ""
}
,
HUYA.Dimension.prototype._clone = function() {
    return new HUYA.Dimension
}
,
HUYA.Dimension.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.Dimension.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.Dimension.prototype.writeTo = function(t) {
    t.writeString(0, this.sName),
    t.writeString(1, this.sValue)
}
,
HUYA.Dimension.prototype.readFrom = function(t) {
    this.sName = t.readString(0, !1, this.sName),
    this.sValue = t.readString(1, !1, this.sValue)
}
,
HUYA.StatsSet = function() {
    this.fSum = 0,
    this.fMaxValue = 0,
    this.fMinValue = 0,
    this.lSampleCnt = 0
}
,
HUYA.StatsSet.prototype._clone = function() {
    return new HUYA.StatsSet
}
,
HUYA.StatsSet.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.StatsSet.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.StatsSet.prototype.writeTo = function(t) {
    t.writeDouble(0, this.fSum),
    t.writeDouble(1, this.fMaxValue),
    t.writeDouble(2, this.fMinValue),
    t.writeInt64(3, this.lSampleCnt)
}
,
HUYA.StatsSet.prototype.readFrom = function(t) {
    this.fSum = t.readDouble(0, !1, this.fSum),
    this.fMaxValue = t.readDouble(1, !1, this.fMaxValue),
    this.fMinValue = t.readDouble(2, !1, this.fMinValue),
    this.lSampleCnt = t.readInt64(3, !1, this.lSampleCnt)
}
,
HUYA.Metric = function() {
    this.sMetricName = "",
    this.vDimension = new Taf.Vector(new HUYA.Dimension),
    this.iTS = 0,
    this.iSuccess = 0,
    this.iRetCode = 0,
    this.fValue = 0,
    this.eUnit = 0,
    this.tStatsSet = new HUYA.StatsSet,
    this.sExtDesc = ""
}
,
HUYA.Metric.prototype._clone = function() {
    return new HUYA.Metric
}
,
HUYA.Metric.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.Metric.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.Metric.prototype.writeTo = function(t) {
    t.writeString(0, this.sMetricName),
    t.writeVector(1, this.vDimension),
    t.writeInt64(2, this.iTS),
    t.writeInt32(3, this.iSuccess),
    t.writeInt32(4, this.iRetCode),
    t.writeDouble(5, this.fValue),
    t.writeInt32(6, this.eUnit),
    t.writeStruct(7, this.tStatsSet),
    t.writeString(8, this.sExtDesc)
}
,
HUYA.Metric.prototype.readFrom = function(t) {
    this.sMetricName = t.readString(0, !0, this.sMetricName),
    this.vDimension = t.readVector(1, !1, this.vDimension),
    this.iTS = t.readInt64(2, !1, this.iTS),
    this.iSuccess = t.readInt32(3, !1, this.iSuccess),
    this.iRetCode = t.readInt32(4, !1, this.iRetCode),
    this.fValue = t.readDouble(5, !1, this.fValue),
    this.eUnit = t.readInt32(6, !1, this.eUnit),
    this.tStatsSet = t.readStruct(7, !1, this.tStatsSet),
    this.sExtDesc = t.readString(8, !1, this.sExtDesc)
}
,
HUYA.MetricSet = function() {
    this.tId = new HUYA.UserId,
    this.vMetric = new Taf.Vector(new HUYA.Metric)
}
,
HUYA.MetricSet.prototype._clone = function() {
    return new HUYA.MetricSet
}
,
HUYA.MetricSet.prototype._write = function(t, e, i) {
    t.writeStruct(e, i)
}
,
HUYA.MetricSet.prototype._read = function(t, e, i) {
    return t.readStruct(e, !0, i)
}
,
HUYA.MetricSet.prototype.writeTo = function(t) {
    t.writeStruct(0, this.tId),
    t.writeVector(1, this.vMetric)
}
,
HUYA.MetricSet.prototype.readFrom = function(t) {
    this.tId = t.readStruct(0, !0, this.tId),
    this.vMetric = t.readVector(1, !0, this.vMetric)
}
;
var TafMx = TafMx || {};
TafMx.UriMapping = {
    6501: HUYA.SendItemSubBroadcastPacket,
    1400: HUYA.MessageNotice,
    8006: HUYA.AttendeeCountNotice
},
TafMx.WupMapping = {
    doLaunch: HUYA.LiveLaunchRsp,
    speak: HUYA.NobleSpeakResp,
    OnUserEvent: HUYA.UserEventRsp,
    getPropsList: HUYA.GetPropsListRsp,
    OnUserHeartBeat: HUYA.UserHeartBeatRsp,
    getLivingInfo: HUYA.GetLivingInfoRsp
};
