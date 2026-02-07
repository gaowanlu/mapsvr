package main

import (
	"dbsvrgo/client"
	"dbsvrgo/db"
	"dbsvrgo/proto_res"
	"dbsvrgo/worker"
	"fmt"
	"log"
	"os"

	"github.com/joho/godotenv"
)

func main() {
	// 生产环境不依靠.env文件
	if os.Getenv("APP_ENV") != "production" {
		err := godotenv.Load()
		if err != nil {
			log.Fatalf("加载 .env 失败: %v", err)
		}
	}

	rpcAddr := os.Getenv("DBSVRGO_RPC_ADDR")
	appId := os.Getenv("DBSVRGO_APPID")

	connStr := ""

	connStr += "host=" + os.Getenv("DBSVRGO_DB_HOST") + " "
	connStr += "port=" + os.Getenv("DBSVRGO_DB_PORT") + " "
	connStr += "user=" + os.Getenv("DBSVRGO_DB_USER") + " "
	connStr += "password=" + os.Getenv("DBSVRGO_DB_PASSWORD") + " "
	connStr += "dbname=" + os.Getenv("DBSVRGO_DB_DBNAME") + " "
	connStr += "sslmode=" + os.Getenv("DBSVRGO_DB_SSLMODE") + " "

	if err := db.Init(connStr); err != nil {
		log.Fatal(err)
	} else {
		fmt.Println("连接DB成功")
	}

	w := worker.New(1024)
	w.Start()

	_, err := client.NewClient(rpcAddr,
		appId,
		func(client *client.Client) error {
			client.SendHandshake() //发送握手
			msg := &proto_res.ProtoCSReqExample{
				TestContext: []byte("进程间通信测试"),
			}
			client.Send(proto_res.ProtoCmd_PROTO_CMD_CS_REQ_EXAMPLE, msg)
			w.SetClient(client)
			return nil
		},

		func(client *client.Client, pkg *proto_res.ProtoPackage) error {
			log.Println("RPC 收到包 CMD =", pkg.Cmd)

			w.Push(pkg)

			log.Println("移交给Worker处理")

			return nil
		})

	if err != nil {
		log.Fatalln("创建RPC client.Client 失败：", err)
	}

	select {}
}
