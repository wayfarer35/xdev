# xdev — 容器化开发环境

提供一个开箱即用的开发环境

PHP
PHP往往需要安装扩展来使用，然而扩展很多时，构建往往非常耗费时间，所以封装了几乎囊括所有PHP的镜像，在使用时通过简单的启用不用每次都重新构建，注意这是为了开发环境的便利，生产环境应该避免不必要的扩展安装


PHP镜像：
- 详见： [docs/prebuilt-php-images.md](docs/prebuilt-php-images.md)



## 用法
复制env
```
# 全局env, 配置个服务的信息
cp examples/.env.example .env

# php扩展env，php版本和.env中的一致
cp examples/php-8.4.env.example .php.env
```

如果需要自定义服务，添加docker-compose.override.yml



启动所有服务
```bash
docker compose up -d
```

启动指定服务
```bash
# 启动nginx
docker compose up -d nginx 

# 启动mysql
docker compose up -d mysql

```

