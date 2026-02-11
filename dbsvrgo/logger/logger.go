package logger

import (
	"github.com/natefinch/lumberjack"
	"github.com/sirupsen/logrus"
)

// 全局日志实例
var Log = logrus.New()

func init() {
	// 配置日志文件的轮转
	Log.SetOutput(&lumberjack.Logger{
		Filename:   "./log/dbsvrgo.log",
		MaxSize:    10,    // MB
		MaxBackups: 30,    // 保留 30 个备份
		MaxAge:     28,    // 日志文件保存 28 天
		Compress:   false, // 是否压缩旧日志
	})

	Log.SetFormatter(&logrus.JSONFormatter{})
	Log.SetLevel(logrus.InfoLevel)

	Log.Info("This is an info message.")
	Log.Warn("This is a warning message.")
	Log.Error("This is an error message.")
}
