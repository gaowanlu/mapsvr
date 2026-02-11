package worker

import (
	"fmt"
	"reflect"

	"google.golang.org/protobuf/encoding/prototext"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/reflect/protoreflect"

	"dbsvrgo/client"
	"dbsvrgo/db"
	"dbsvrgo/logger"
	"dbsvrgo/mapper"
	"dbsvrgo/proto_res"
)

type CmdHandler func(w *Worker, pkg *proto_res.ProtoPackage)

// worker 接收消息进行操作
type Worker struct {
	ch       chan *proto_res.ProtoPackage // 通道
	client   *client.Client
	handlers map[proto_res.ProtoCmd]CmdHandler
}

// 创建worker size为通道最多等待处理消息大小
func New(size int) *Worker {
	w := &Worker{ch: make(chan *proto_res.ProtoPackage, size),
		client:   nil,
		handlers: make(map[proto_res.ProtoCmd]CmdHandler)}
	w.registerHandlers()
	return w
}

func (w *Worker) SetClient(client *client.Client) {
	w.client = client
}

func (w *Worker) Start() {
	go func() {
		for pkg := range w.ch {

			handler, ok := w.handlers[pkg.Cmd]
			if !ok {
				logger.Log.Println("未知的指令 CMD =", pkg.Cmd)
				continue
			}

			handler(w, pkg)
		}
	}()
}

func (w *Worker) ExecWriteOper(msg proto.Message) error {
	sqlStr, args, err := mapper.BuildSQL(msg)
	logger.Log.Println("ExecWriteOper SQL => ", sqlStr)
	if err != nil {
		logger.Log.Println("build sql error:", err)
		return err
	}

	result, err := db.DB.Exec(sqlStr, args...)
	if err != nil {
		logger.Log.Println("exec error:", err, sqlStr)
		return err
	}

	// 受影响的行数
	rows, err := result.RowsAffected()
	if err != nil {
		logger.Log.Println("RowsAffected error:", err)
	} else {
		logger.Log.Println("Rows affected:", rows)
	}

	// 如果是 INSERT，可获取自增 ID
	if id, err := result.LastInsertId(); err == nil {
		logger.Log.Println("Last insert id:", id)
	}

	return nil
}

// 将写入操作写入worker通道令其处理
func (w *Worker) Push(msg *proto_res.ProtoPackage) {
	w.ch <- msg
}

// SelectRaw 用于执行 SELECT 查询，并将结果行反序列化为 proto.Message 切片
// msg   : 一个 proto Message 模板（用于 Clone 和反射字段信息）
// where : SQL 的 where 条件（如 "user_id=123"）
func (w *Worker) SelectRaw(msg proto.Message, where string, args ...any) ([]proto.Message, error) {

	// 通过 mapper 构建 SELECT SQL 语句
	// sqlStr : 完整的 SELECT SQL
	// meta   : proto 与数据库字段的映射元信息（字段顺序、类型等）
	sqlStr, meta, err := mapper.BuildSelectRawSQL(msg, where, args...)
	if err != nil {
		return nil, err
	}
	fmt.Println("SelectRaw => ", sqlStr)

	// 执行查询
	rows, err := db.DB.Query(sqlStr, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	// 用于保存最终反序列化后的 proto Message 列表
	var results []proto.Message

	// 遍历结果集的每一行
	for rows.Next() {

		// Clone 一个新的 proto Message，作为当前行的承载对象
		// 不能直接复用 msg，否则数据会互相覆盖
		m := proto.Clone(msg)

		// 获取 proto 的反射接口，用于后续动态 Set 字段
		pm := m.ProtoReflect()

		// holders     : 保存 Scan 的真实变量地址
		// scanArgs    : 传给 rows.Scan 的参数列表
		holders := make([]any, len(meta.Fields))
		scanArgs := make([]any, len(meta.Fields))

		// 根据字段类型，构造 Scan 需要的接收变量
		for i, f := range meta.Fields {
			fd := f.Fd // proto 字段描述符

			// 如果是 message 类型（嵌套结构）
			// 数据库中通常以 blob / json / bytes 形式存储
			if fd.Kind() == protoreflect.MessageKind {
				var b []byte
				holders[i] = &b
			} else {
				// 普通标量类型，根据 proto 字段类型生成 Go 变量
				// reflect.New 返回 *T，用于 Scan
				holders[i] = reflect.New(goType(fd)).Interface()
			}

			// Scan 参数本质就是指针切片
			scanArgs[i] = holders[i]
		}

		// 将当前行的数据扫描到 holders 中
		if err := rows.Scan(scanArgs...); err != nil {
			return nil, err
		}

		// 将 holders 中的数据写回 proto Message
		for i, f := range meta.Fields {
			fd := f.Fd
			v := holders[i]

			// 如果是 message 字段（嵌套 proto）
			if fd.Kind() == protoreflect.MessageKind {

				// 数据库存的是序列化后的 bytes
				b := *(v.(*[]byte))

				// 获取 proto 中该字段的可变 message
				sub := pm.Mutable(fd).Message()

				// 非空才反序列化，避免 Unmarshal 空数据
				if len(b) > 0 {
					_ = proto.Unmarshal(b, sub.Interface())
				}
			} else {
				// 普通标量字段，调用统一的 setScalar 写入
				setScalar(pm, fd, v)
			}
		}

		// 当前行反序列化完成，加入结果集
		results = append(results, m)
	}

	return results, nil
}

// goType 根据 proto 字段类型，返回对应的 Go reflect.Type
// 用于 rows.Scan 接收 PostgreSQL 字段值
func goType(fd protoreflect.FieldDescriptor) reflect.Type {
	switch fd.Kind() {
	case protoreflect.Int32Kind:
		return reflect.TypeOf(int32(0)) // INTEGER 对应 int32
	case protoreflect.Int64Kind:
		return reflect.TypeOf(int64(0)) // BIGINT 对应 int64
	case protoreflect.StringKind:
		return reflect.TypeOf("") // TEXT 对应 string
	case protoreflect.BoolKind:
		return reflect.TypeOf(false) // BOOLEAN 对应 bool
	case protoreflect.FloatKind:
		return reflect.TypeOf(float32(0)) // REAL 对应 float32
	case protoreflect.DoubleKind:
		return reflect.TypeOf(float64(0)) // DOUBLE PRECISION 对应 float64
	case protoreflect.BytesKind:
		return reflect.TypeOf([]byte{}) // BYTEA 对应 []byte
	default:
		// 不支持的类型返回 nil（理论上不会走到）
		return reflect.TypeOf(nil)
	}
}

// setScalar 将 Scan 得到的 Go 基础类型值写入 proto Message
// pm : proto 的反射对象
// fd : 字段描述符
// v  : Scan 得到的 *T
func setScalar(pm protoreflect.Message, fd protoreflect.FieldDescriptor, v any) {

	// v 是 *T，先取 Elem 得到真实值
	var rv reflect.Value = reflect.ValueOf(v).Elem()

	switch fd.Kind() {
	case protoreflect.Int32Kind:
		pm.Set(fd, protoreflect.ValueOfInt32(int32(rv.Int())))
	case protoreflect.Int64Kind:
		pm.Set(fd, protoreflect.ValueOfInt64(rv.Int()))
	case protoreflect.StringKind:
		pm.Set(fd, protoreflect.ValueOfString(rv.String()))
	case protoreflect.BoolKind:
		pm.Set(fd, protoreflect.ValueOfBool(rv.Bool()))
	case protoreflect.FloatKind:
		pm.Set(fd, protoreflect.ValueOfFloat32(float32(rv.Float())))
	case protoreflect.DoubleKind:
		pm.Set(fd, protoreflect.ValueOfFloat64(rv.Float()))
	case protoreflect.BytesKind:
		pm.Set(fd, protoreflect.ValueOfBytes(rv.Bytes())) // 处理 BYTEA 类型
	}
}

func (w *Worker) handleHandshake(pkg *proto_res.ProtoPackage) {
	var msg proto_res.ProtoIPCStreamAuthHandshake
	if err := proto.Unmarshal(pkg.Protocol, &msg); err != nil {
		logger.Log.Println("解析失败:", err)
		return
	}
	logger.Log.Println("RPC握手成功 AppId:", string(msg.AppId))
}

func (w *Worker) handleExampleRes(pkg *proto_res.ProtoPackage) {
	var msg proto_res.ProtoCSResExample
	if err := proto.Unmarshal(pkg.Protocol, &msg); err != nil {
		logger.Log.Println("解析失败:", err)
		return
	}

	appId := ""
	if w.client != nil {
		appId = w.client.GetAppId()
	}

	logger.Log.Printf(
		"RPC发来消息 AppId %s: ProtoCmd_PROTO_CMD_CS_RES_EXAMPLE %s",
		appId,
		string(msg.TestContext),
	)
}

func (w *Worker) handleWriteUserRecord(pkg *proto_res.ProtoPackage) {
	var msg proto_res.DbUserRecord
	if err := proto.Unmarshal(pkg.Protocol, &msg); err != nil {
		logger.Log.Println("解析失败:", err)
		return
	}

	logger.Log.Println(prototext.Format(&msg))
	w.ExecWriteOper(&msg)
}

func (w *Worker) handleSelectUserRecord(pkg *proto_res.ProtoPackage) {
	var msg proto_res.SelectDbUserRecordReq
	if err := proto.Unmarshal(pkg.Protocol, &msg); err != nil {
		logger.Log.Println("解析失败:", err)
		return
	}

	logger.Log.Println(prototext.Format(&msg))

	res, err := w.SelectRaw(&proto_res.DbUserRecord{}, msg.Where)
	if err != nil {
		logger.Log.Println("select error:", err)
		return
	}

	resMsg := &proto_res.SelectDbUserRecordRes{}
	for _, m := range res {
		resMsg.UserRecordList = append(resMsg.UserRecordList, m.(*proto_res.DbUserRecord))
	}

	logger.Log.Println(prototext.Format(resMsg))
	w.client.Send(proto_res.ProtoCmd_PROTO_CMD_DBSVRGO_SELECT_DBUSERRECORD_RES, resMsg)
}

func (w *Worker) handleInsertDbUserRecordReq(pkg *proto_res.ProtoPackage) {
	var msg proto_res.InsertDbUserRecordReq
	if err := proto.Unmarshal(pkg.Protocol, &msg); err != nil {
		logger.Log.Println("解析失败:", err)
		return
	}

	msg.DbUserRecord.Op = proto_res.DbOpType_OP_INSERT
	err := w.ExecWriteOper(msg.DbUserRecord)

	var msgRes proto_res.InsertDbUserRecordRes
	msgRes.ClientGID = msg.ClientGID
	msgRes.Ret = 0
	msgRes.WorkerIdx = msg.WorkerIdx

	if err != nil {
		msgRes.Ret = -1

	} else {
		res, err := w.SelectRaw(&proto_res.DbUserRecord{}, "id=$1 limit 1", msg.DbUserRecord.Id)
		if err != nil {
			logger.Log.Println("select error:", err)
			msgRes.Ret = -1
		} else {
			if len(res) > 0 {
				msgRes.DbUserRecord = res[0].(*proto_res.DbUserRecord)
				logger.Log.Println(prototext.Format(msgRes.DbUserRecord))
			} else {
				msgRes.Ret = -1
			}

		}
	}

	w.client.Send(proto_res.ProtoCmd_PROTO_CMD_DBSVRGO_INSERT_DBUSERRECORD_RES, &msgRes)

	logger.Log.Println(prototext.Format(&msgRes))
}

func (w *Worker) handleSelectDbUserRecordLoginReq(pkg *proto_res.ProtoPackage) {
	var req proto_res.SelectDbUserRecordLoginReq
	if err := proto.Unmarshal(pkg.Protocol, &req); err != nil {
		logger.Log.Println("解析失败:", err)
		return
	}

	var res proto_res.SelectDbUserRecordLoginRes
	res.PlayerId = req.PlayerId
	res.ClientGID = req.ClientGID
	res.WorkerIdx = req.WorkerIdx
	res.UserId = req.UserId
	res.Password = req.Password
	res.Ret = 0

	selectRes, err := w.SelectRaw(&proto_res.DbUserRecord{}, "user_id=$1 limit 1", req.UserId)
	if err != nil {
		logger.Log.Println("select error:", err)
		res.Ret = -1
	} else {
		if len(selectRes) > 0 {
			res.UserRecord = selectRes[0].(*proto_res.DbUserRecord)
			logger.Log.Println(prototext.Format(res.UserRecord))
		} else {
			res.Ret = -1
		}

	}

	w.client.Send(proto_res.ProtoCmd_PROTO_CMD_DBSVRGO_SELECT_DBUSERRECORD_LOGIN_RES, &res)
}

func (w *Worker) registerHandlers() {

	w.handlers[proto_res.ProtoCmd_PROTO_CMD_IPC_STREAM_AUTH_HANDSHAKE] =
		(*Worker).handleHandshake

	w.handlers[proto_res.ProtoCmd_PROTO_CMD_CS_RES_EXAMPLE] =
		(*Worker).handleExampleRes

	w.handlers[proto_res.ProtoCmd_PROTO_CMD_DBSVRGO_WRITE_DBUSERRECORD_REQ] =
		(*Worker).handleWriteUserRecord

	w.handlers[proto_res.ProtoCmd_PROTO_CMD_DBSVRGO_SELECT_DBUSERRECORD_REQ] =
		(*Worker).handleSelectUserRecord

	w.handlers[proto_res.ProtoCmd_PROTO_CMD_DBSVRGO_INSERT_DBUSERRECORD_REQ] =
		(*Worker).handleInsertDbUserRecordReq

	w.handlers[proto_res.ProtoCmd_PROTO_CMD_DBSVRGO_SELECT_DBUSERRECORD_LOGIN_REQ] =
		(*Worker).handleSelectDbUserRecordLoginReq
}
