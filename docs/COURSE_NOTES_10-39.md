# Конспект курса: темы 10–39

Краткое объяснение оставшейся части курса своими словами, привязанное к реальному коду в этом репозитории — чтобы не смотреть ~3 часа видео.

---

## 10. Что такое OpenSearch?

OpenSearch — форк Elasticsearch (Amazon сделал его после того, как Elastic сменил лицензию на не полностью open-source). Это поисковый движок + аналитическая база на базе Lucene: данные хранятся в виде JSON-документов, разбитых на **индексы**, индексы физически разбиты на **шарды** (см. тему 37).

В этом репо OpenSearch используется как **managed-сервис AWS** (`terraform/modules/opensearch`) — то есть AWS сам управляет нодами, патчами, репликацией. Это альтернатива темам 21–34, где Elasticsearch поднимается вручную на своих EC2 (ECS или Docker Swarm). Managed OpenSearch проще в поддержке, но менее гибкий и обычно дороже за эквивалентные ресурсы.

## 11–14. Terraform OpenSearch модуль (4 части)

Модуль `terraform/modules/opensearch` состоит из одного основного ресурса `aws_opensearch_domain` (`es.tf`), который курс для удобства объяснения разбивает на 4 логических блока:

- **Часть 1 — security and permissions**: `main.tf` (провайдер) + `locals.tf` (общие теги/префикс имени). В `es.tf` сюда же относится `access_policies` (JSON policy, кто может стучаться в домен — в шаблоне открыто на `"Principal": "*"`, что нормально только потому что доступ и так ограничен security group/VPC) и `advanced_security_options` (fine-grained access control, тут выключен).
- **Часть 2 — cluster configuration**: `cluster_config` в `es.tf` — тип и количество инстансов (`instance_type`, `instance_count`), `zone_awareness` — размазывает ноды по нескольким AZ для отказоустойчивости.
- **Часть 3 — network, logs and storage**: `vpc_options` (в какие сабнеты и security groups садится домен — see `sg-es.tf`), `ebs_options` (диски, `gp2`), `logs.tf` (CloudWatch Log Group для логов домена), `log_publishing_options` (какие логи туда льются — `ES_APPLICATION_LOGS`, `SEARCH_SLOW_LOGS`).
- **Часть 4 — CW alarms и variables**: `alarms.tf` (CloudWatch alarms на CPU, свободное место, статус кластера — в текущем виде **закомментированы**, это шаблон "раскомментируй и подключи SNS, если нужны алерты"), `variables.tf`/`variables-env.tf` — весь интерфейс модуля.

## 15. Важные ошибки и как их решать

Это как раз то, с чем мы столкнулись в этой сессии на практике:
- **Имя S3-бакета для state должно быть глобально уникальным** во всём AWS, а не только в твоём аккаунте — если взять имя "в лоб" (`terraform-state-aws-es-devops`), оно почти наверняка уже занято другим студентом курса → получишь `403 Forbidden`, а не `404`, потому что S3 не палит существование чужих бакетов.
- Если тестируешь с чужим/старым `.tfstate` (склонированным из репозитория с чужими ARN аккаунтов) — Terraform будет пытаться управлять ресурсами не в твоём аккаунте. Решение — удалить локальный state и начать с чистого листа под своим account_id.
- Учётные данные AWS CLI должны быть в стандартном формате, который понимает AWS SDK (статические ключи через `aws configure`, либо нормальный SSO) — экспериментальные механики типа `aws login` (root browser-login) Terraform provider может не распознать.

## 16. Применение OpenSearch модуля, endpoint и Dashboard

`terraform/dev/opensearch` — вызов модуля с конкретными параметрами для dev. После `apply` AWS выдаёт **domain endpoint** (обычный REST API, `https://<endpoint>/_cluster/health`) и отдельный **Dashboards endpoint** (`.../_dashboards`) — это веб-UI (аналог Kibana). Так как домен сидит в VPC без публичного доступа, до Dashboards достаёшься через SSH-туннель на бастион (см. пример `LocalForward` в README) — это ровно то, что объяснялось про бастион.

## 17. OpenSearch monitoring

Мониторинг тут — это связка **CloudWatch metrics** (автоматически собираются AWS: CPUUtilization, FreeStorageSpace, ClusterStatus.green/yellow/red, JVMMemoryPressure, Nodes) + опциональные alarms из `alarms.tf` + `log_publishing_options` из `logs.tf` (application logs, slow logs) для более глубокой диагностики запросов, которые тормозят.

## 18. Итоги по OpenSearch и заметки из коммерческой практики

Типичные "грабли" managed OpenSearch на практике:
- Managed-сервис **дороже** за единицу CPU/RAM, чем самостоятельно управляемый ES на EC2 — плата за то, что не надо патчить/чинить ноды самому.
- Апгрейд версии engine иногда требует blue/green передеплоя AWS "под капотом" — может занять время и повлиять на доступность.
- `instance_count`/`az_count` жёстко влияют на стоимость — zone awareness с 3 AZ утраивает минимальный набор нод.
- Ограниченный доступ к low-level настройкам кластера (в отличие от self-managed, где ты правишь `elasticsearch.yml` напрямую).

## 19. AWS OpenSearch Benchmarks *(пропущено — код/материалов в репозитории нет)*

## 20. OpenSearch ML reranking с AWS Personalize *(пропущено — код/материалов в репозитории нет)*

## 21. Что такое ECS и почему EC2, а не Fargate

**ECS (Elastic Container Service)** — оркестратор контейнеров от AWS (альтернатива Kubernetes, но проще). У ECS два launch type:
- **Fargate** — serverless, AWS сам управляет "нодами", ты просто платишь за CPU/RAM контейнера.
- **EC2** — ты сам поднимаешь EC2-инстансы, которые становятся ECS-нодами (`terraform/modules/ecs-ec2`), а ECS уже раскидывает контейнеры по ним.

Почему в курсе выбран **EC2**, а не Fargate — для Elasticsearch критичны:
- **Persistent volumes** с предсказуемым поведением (в `ecs.tf` видно `volume { host_path = "/usr/share/elasticsearch/data" }` — это bind-mount на диск конкретной EC2-ноды, у Fargate такого контроля над диском нет),
- Настройка `sysctl` уровня хоста (`vm.max_map_count=262144` — обязательный параметр ядра для Elasticsearch, задаётся в userdata EC2, недоступно в Fargate),
- Экономика: при стабильной постоянной нагрузке EC2 обычно дешевле, чем Fargate за тот же CPU/RAM.

## 22. Базовые компоненты и архитектура ECS

Ключевые сущности (все видны в `terraform/modules/ecs-cluster`):
- **ECS Cluster** (`aws_ecs_cluster`) — логическая группировка.
- **Task Definition** (`aws_ecs_task_definition`, шаблон `templates/es.json`) — описание контейнера: образ, порты (9200/9300), память/CPU, volumes, логирование в CloudWatch (`awslogs`).
- **Service** (`aws_ecs_service`) — следит, чтобы нужное число копий таски было живо (`desired_count = 3`), с `placement_constraints { type = "distinctInstance" }` — гарантирует, что 3 таски сядут на 3 **разных** EC2-инстанса, а не скучатся на одном.
- **Execution Role vs Task Role** (`execution-role.tf`, `task-role.tf`) — Execution Role нужна ECS-агенту/докер-демону, чтобы тянуть образ из ECR и писать логи; Task Role — это то, от чьего имени сам контейнер стучится в другие AWS-сервисы (например, S3 для snapshot-репозитория).

## 23. Elasticsearch Dockerfile и AWS ECR

`docker-images/elastisearch/Dockerfile`:
```dockerfile
FROM elasticsearch:7.17.0
ADD elasticsearch.yml /usr/share/elasticsearch/config/
RUN bin/elasticsearch-plugin install -b discovery-ec2 && bin/elasticsearch-plugin install -b repository-s3
```
Это кастомный образ поверх официального — добавляет два плагина:
- **discovery-ec2** — позволяет нодам находить друг друга через AWS API (по тегам EC2-инстансов), а не через захардкоженные IP.
- **repository-s3** — позволяет делать snapshot/restore индексов прямо в S3-бакет.

Собранный образ пушится в **ECR** (Elastic Container Registry — приватный docker-registry AWS), команды есть в README:
```
docker login -u AWS -p $(aws ecr get-login-password ...) ...
docker build . -t ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPO_NAME}:latest
docker push ...
```
ECS потом тянет образ именно из ECR (`docker_image_url_es` в `es.json`).

## 24. ECS IAM profile модуль

`terraform/modules/ecs-iam-profile` — готовит IAM instance profile, который вешается на EC2-ноды ECS-кластера, чтобы:
- ECS-агент на хосте мог зарегистрировать инстанс в кластере,
- Хост мог тянуть образы из ECR,
- писать логи в CloudWatch.

Без этого профиля EC2-инстанс поднимется, но не сможет "присоединиться" к ECS-кластеру.

## 25. ECS EC2 модуль

`terraform/modules/ecs-ec2` — сами EC2-инстансы, которые становятся worker-нодами кластера. Ключевая часть — `userdata.sh.tpl`, который выполняется при старте инстанса:
- `echo 'ECS_CLUSTER=es-cluster' > /etc/ecs/ecs.config` — говорит ECS-агенту, к какому кластеру примкнуть,
- выставляет `vm.max_map_count` и `fs.file-max` (обязательно для ES),
- готовит директории для volumes, которые потом монтирует Task Definition.

## 26. ECS cluster модуль

`terraform/modules/ecs-cluster` — уровень оркестрации: сам `aws_ecs_cluster`, Task Definition (рендерится из `templates/es.json` через `template_file` с подстановкой `docker_image_url_es`/`region`), Service с `desired_count=3` и `distinctInstance` placement, плюс IAM-роли (execution/task) и `logs.tf` (CloudWatch Log Group `ec2-ecs-es`).

## 27. Итоги: Elasticsearch на ECS

Плюсы ECS-подхода: полноценный оркестратор — автоматический реролл контейнеров при падении хоста/таски, встроенная интеграция с ALB/CloudWatch/IAM, декларативная модель (task definition = версия конфигурации, можно откатиться). Минусы: сложнее в освоении, чем "просто докер на EC2" (Docker Swarm), больше движущихся частей (execution role, task role, task definition, service, placement).

## 28. Что такое Docker Swarm и почему он не мёртв

Docker Swarm — встроенный в сам Docker оркестратор контейнеров (`docker swarm init`, `docker service create`). Все считают, что рынок съел Kubernetes, но Swarm жив там, где: небольшой/средний кластер, не нужна вся сложность k8s (CRD, operators, Helm), команда маленькая и хочет минимальный порог входа — по сути "написал `docker-compose`-подобный сервис — и он размазался по нодам с встроенным service discovery и балансировкой".

## 29. Архитектура Docker Swarm

Роли нод:
- **Manager nodes** — держат состояние кластера (Raft consensus), принимают команды `docker service ...`, планируют, куда какая таска едет.
- **Worker nodes** — просто исполняют назначенные им таски (контейнеры).

В этом репо это видно из `ansible/roles/docker-swarm` (инициализация/join нод) и в `elasticsearch-docker` роли — задача `docker_swarm_service` выполняется `when: inventory_hostname == docker_swarm__run_manager`, то есть команда на создание/обновление сервиса ES отдаётся именно с manager-ноды, а сам сервис через `mode: global` разъезжается на все подходящие ноды (по `node.labels.<name> == enabled` — таргетинг через лейблы нод).

## 30. EC2 модуль

`terraform/modules/ec2` (в отличие от `ecs-ec2`) — это чистые EC2-инстансы **без ECS**, предназначенные под Docker Swarm сценарий. Инстанс садится в конкретную AZ (`element([for s in var.subnets : s.id if s.availability_zone == var.az], 0)`), без публичного IP (`associate_public_ip_address = false` — снова паттерн "доступ только через бастион"), с `gp3` диском. Дальше Ansible (см. п.31–32) уже ставит на эти голые EC2 docker + swarm + сам сервис Elasticsearch.

## 31. Ansible inventory, docker и docker swarm роли

- `ansible/inventories/dev/hosts` + `group_vars/*.yml` — описывают, какие хосты (app-a/b/c, bastion) в какие группы входят и с какими переменными.
- `roles/docker-installation` — ставит сам Docker Engine (`tasks/main.yml`), включая переопределение конфига containerd (`files/override_containerd.conf`).
- `roles/docker-swarm` (сторонний community-role, есть `LICENSE`/`README.md`) + `roles/docker-swarm-common` (свои общие таски/фильтры) — инициализируют Swarm-кластер: первая нода делает `docker swarm init`, остальные джойнятся как workers/managers через join-token.
- `roles/install-modules` / `roles/set-hostnames` — вспомогательные роли (python-модули для Ansible, выставление hostname по AWS-тегам).

## 32. Ansible Elasticsearch роль

`roles/elasticsearch-docker` — уже прикладной уровень поверх готового Swarm-кластера:
1. Создаёт директории на хосте под конфиги и данные ES (`elasticsearch_etc_dir`, `elasticsearch_data_dir`).
2. Рендерит `elasticsearch.yml`, `jvm.options`, `log4j2.properties` из переменных (`defaults/main.yml`) — то есть конфиг ES целиком управляется через Ansible-переменные, а не руками на сервере.
3. Выставляет `vm.max_map_count=262144` через sysctl.
4. Пуллит образ ES (`docker.elastic.co/elasticsearch/elasticsearch:7.17.5`).
5. Создаёт сам **Swarm service** `docker_swarm_service` с `mode: global` (по одному контейнеру на каждую подходящую ноду), с bind-mount конфига и данных, стратегией rolling update (`update_config`: по одной ноде за раз, `order: stop-first`) и rollback-стратегией на случай сбоя.

Плейбук `playbooks/full_es_env.yml` — точка входа, которая раскатывает всё окружение целиком одной командой.

## 33. Итоги: Elasticsearch на Docker Swarm

Плюсы: простота (Swarm встроен в Docker, минимум внешних зависимостей), полный контроль над конфигом ES (правишь `elasticsearch.yml` напрямую через Ansible-переменные), дешевле ECS (нет доп. IAM/orchestration overhead). Минусы: меньше "коробочных" интеграций с AWS (нет нативного service discovery через AWS API, как `discovery-ec2` плагин в ECS-сценарии — тут вместо этого используется swarm-networking), вся отказоустойчивость/апдейты — на тебе через Ansible, а не через managed control plane.

## 34. Autoscaling Elasticsearch на AWS

Для stateful-сервиса типа Elasticsearch автоскейлинг нетривиален (в отличие от stateless web-приложений) — новую ноду нельзя просто "выключить", не переместив с неё шарды, иначе потеряешь данные или уронишь availability. Практический подход (о котором рассказывает лекция): рост через **добавление нод в кластер** с последующим `_cluster/reroute` / автоматическим шардовым ребалансом (ES сам перераспределяет шарды на новые ноды по мере готовности), либо через managed OpenSearch — там AWS частично берёт этот процесс на себя при изменении `instance_count`. Для самостоятельно управляемого кластера (ECS/Swarm) под это обычно пишут отдельную логику (CloudWatch alarm на нагрузку → Lambda/ASG → добавление ноды → drain/rebalance перед удалением).

## 35. Итоги курса: какой сценарий деплоя лучше?

Три варианта из этого репо, если сравнивать:

| Критерий | Managed OpenSearch | ECS (EC2) | Docker Swarm (EC2) |
|---|---|---|---|
| Простота поддержки | Высокая (AWS всё делает) | Средняя | Средняя-низкая (всё вручную) |
| Контроль над конфигом | Низкий | Высокий | Максимальный |
| Стоимость | Выше за unit ресурса | Средняя | Обычно дешевле |
| Порог входа | Низкий | Средний (нужно знать ECS) | Средний (нужно знать Swarm/Ansible) |
| Подходит для | MVP, команда без DevOps-ресурса | Компании, уже живущие в AWS/ECS-экосистеме | Команды, которым важен полный контроль и минимум vendor lock-in |

## 36. Внутри кластера

Как физически устроен Elasticasearch/OpenSearch кластер: несколько **нод** объединены в один кластер по имени (`cluster.name`), у нод есть роли (master-eligible, data, ingest, coordinating). **Master-нода** отвечает за состояние кластера (какие индексы есть, где лежат шарды) — это ровно то, что настраивается через `cluster.initial_master_nodes` в userdata EC2-сценария. Данные физически хранятся в виде **шардов** (см. следующий пункт), а клиентские запросы могут прилетать на любую ноду — она сама координирует сбор ответа с нужных шардов.

## 37. Elasticsearch — шарды и производительность

Каждый **индекс** делится на N **primary shards** (задаётся при создании индекса, потом не меняется без reindex) — это позволяет размазать данные и нагрузку по нодам и параллелить поиск. У каждого primary есть N **replica shards** — копии для отказоустойчивости и чтения (реплики можно обслуживать читающие запросы, разгружая primary).

Практические выводы для производительности:
- **Слишком много мелких шардов** — overhead на метаданные и heap каждой ноды (по грубому правилу — десятки ГБ на шард, не сотни мелких).
- **Слишком мало крупных шардов** — не параллелится, узкое место на одной ноде, долгий reindex/recovery.
- Реплики (`instance_count`/`az_count` в терраформ-модуле OpenSearch) — это не только "бэкап", это ещё и throughput на чтение.
- `zone_awareness` (в `es.tf`) — размазывает primary/replica по разным AZ, чтобы падение одной AZ не роняло данные.

## 38. Секреты индексации

Практические приёмы для быстрой и правильной индексации (то, что обычно всплывает в реальной эксплуатации):
- **Bulk API** вместо индексации по одному документу — на порядок быстрее за счёт меньшего числа round-trip'ов.
- Отключение `refresh_interval` (или увеличение) на время массовой загрузки — refresh — дорогая операция, которая делает новые документы видимыми для поиска, но не нужна на каждый чих во время bulk-импорта.
- Уменьшение `number_of_replicas` до 0 на время начальной загрузки, включение обратно после — меньше write amplification.
- Правильный выбор **типов полей** (`keyword` vs `text`, `mapping` заранее, а не на автодетекте) — неправильный автомаппинг — частая причина раздутых индексов и медленных агрегаций.
- ID документов: если не важен свой ID — не задавай его вручную, автогенерация у ES оптимизирована лучше, чем route-by-custom-id в некоторых сценариях.

## 39. Bonus Lecture *(бонусный контент — без отдельного кода в репозитории)*

---

### Как это всё соотносится с файлами репозитория

| Тема | Файлы |
|---|---|
| OpenSearch модуль | `terraform/modules/opensearch/*`, `terraform/dev/opensearch/*` |
| ECS | `terraform/modules/ecs-iam-profile`, `ecs-ec2`, `ecs-cluster` + `terraform/dev/ecs-*` |
| Docker образ ES | `docker-images/elastisearch/*` |
| Docker Swarm / Ansible | `ansible/roles/docker-installation`, `docker-swarm`, `docker-swarm-common`, `elasticsearch-docker`, `ansible/playbooks/*` |
| EC2 для Swarm | `terraform/modules/ec2`, `terraform/dev/ec2` |
