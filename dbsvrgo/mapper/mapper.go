package mapper

import (
	"fmt"
	"regexp"
	"strings"
	"sync"

	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/reflect/protoreflect"

	"dbsvrgo/logger"
	p "dbsvrgo/proto_res"
)

// camelToSnakeCase 将驼峰命名转为下划线命名
func camelToSnakeCase(str string) string {
	// 正则表达式匹配大写字母，并在其前添加下划线
	re := regexp.MustCompile("([a-z])([A-Z])")
	// 替换为小写字母，并用下划线分隔
	str = re.ReplaceAllString(str, "${1}_${2}")
	// 转换为全小写
	res := strings.ToLower(str)
	logger.Log.Println("func camelToSnakeCase ", str, " ", res)
	return res
}

// 表字段名称
type FieldInfo struct {
	Name string
	Fd   protoreflect.FieldDescriptor
}

// 表结构
type MetaInfo struct {
	Table  string      // 表名
	Fields []FieldInfo // 表结构
}

// 缓存表结构
var metaCache sync.Map

// 根据protobuf表Message获取表结构
func getMeta(msg proto.Message) *MetaInfo {
	// 获取消息名
	full := string(msg.ProtoReflect().Descriptor().FullName())
	// 缓存命中
	if v, ok := metaCache.Load(full); ok {
		return v.(*MetaInfo) // 返回表结构
	}

	// 获取消息的反射
	m := msg.ProtoReflect()
	desc := m.Descriptor()

	// 表名统一SnakeCase
	meta := &MetaInfo{
		Table: camelToSnakeCase(string(desc.Name())),
	}

	// 消息内部字段
	fds := desc.Fields()
	for i := 0; i < fds.Len(); i++ {
		fd := fds.Get(i)
		name := string(fd.Name())
		// op是一个特殊字段用于操作数据
		if name == "op" {
			continue
		}
		// 追加到Fields中
		meta.Fields = append(meta.Fields, FieldInfo{Name: name, Fd: fd})
	}

	// 存到缓存中
	metaCache.Store(full, meta)
	return meta
}

// 写入操作SQL
func BuildSQL(msg proto.Message) (string, []any, error) {
	m := msg.ProtoReflect()
	meta := getMeta(msg)

	var (
		cols  []string
		vals  []any
		sets  []string
		idVal any
		op    p.DbOpType
	)

	opField := m.Descriptor().Fields().ByName("op")
	op = p.DbOpType(m.Get(opField).Enum())

	// 遍历表每个字段 必须要有一个id字段
	foundIdField := false
	for _, fi := range meta.Fields {
		f := fi.Fd
		name := fi.Name // 列名
		v := m.Get(f)   // 从消息中获取值

		if name == "id" { // 任何表统一有一个主键列名id
			foundIdField = true
			idVal = v.Interface()
		}

		var val any
		// 如果字段为一个Message则转为序列化二进制数据
		if f.Kind() == protoreflect.MessageKind {
			b, err := proto.Marshal(v.Message().Interface())
			if err != nil {
				return "", nil, err
			}
			val = b
		} else {
			val = v.Interface()
		}

		// 先将主键id排除
		if name != "id" {
			// 列名追加
			cols = append(cols, name)
			// 列值追加
			vals = append(vals, val)
		}
	}

	if foundIdField == false {
		return "", vals, fmt.Errorf("not found field id in table %s", meta.Table)
	}

	// 生成PostgreSQL风格的占位符 $1, $2, $3...
	var placeholders []string
	for i := 1; i <= len(cols); i++ {
		placeholders = append(placeholders, fmt.Sprintf("$%d", i))
	}

	// 生成SET子句的占位符
	for i, name := range cols {
		sets = append(sets, fmt.Sprintf("%s=$%d", name, i+1))
	}

	switch op {
	// 行插入数据
	case p.DbOpType_OP_INSERT:
		return fmt.Sprintf(
			"INSERT INTO %s(%s,id) VALUES(%s)",
			meta.Table, strings.Join(cols, ","), strings.Join(append(placeholders, fmt.Sprintf("$%d", len(cols)+1)), ","),
		), append(vals, idVal), nil
	// 行Replace主键存在则更新否则插入
	case p.DbOpType_OP_REPLACE:
		// PostgreSQL使用INSERT ... ON CONFLICT代替REPLACE
		return fmt.Sprintf(
			"INSERT INTO %s(%s,id) VALUES(%s) ON CONFLICT (id) DO UPDATE SET %s",
			meta.Table, strings.Join(cols, ","), strings.Join(append(placeholders, fmt.Sprintf("$%d", len(cols)+1)), ","), strings.Join(sets, ","),
		), append(vals, idVal), nil
	// 根据主键行更新
	case p.DbOpType_OP_UPDATE:
		return fmt.Sprintf(
			"UPDATE %s SET %s WHERE id=$%d",
			meta.Table, strings.Join(sets, ","), len(vals)+1,
		), append(vals, idVal), nil
	// 根据主键行删除
	case p.DbOpType_OP_DELETE:
		return fmt.Sprintf(
			"DELETE FROM %s WHERE id=$1",
			meta.Table,
		), []any{idVal}, nil
	}

	return "", nil, fmt.Errorf("unknown op")
}

// 检索行
func BuildSelectRawSQL(msg proto.Message, where string, args ...any) (string, *MetaInfo, error) {
	meta := getMeta(msg)

	cols := make([]string, 0, len(meta.Fields))
	for _, f := range meta.Fields {
		if f.Name != "op" { // op这个字段比较特殊
			cols = append(cols, f.Name)
		}
	}

	sqlStr := fmt.Sprintf(
		"SELECT %s FROM %s",
		strings.Join(cols, ","),
		meta.Table,
	)

	// 加上自定义的where后的内容
	if strings.TrimSpace(where) != "" {
		sqlStr += " WHERE " + where
	}

	return sqlStr, meta, nil
}
