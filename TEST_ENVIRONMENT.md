# OFZ Oracle Test Environment

Это руководство описывает процесс настройки тестового окружения для системы оракула цен ОФЗ, включая развертывание смарт-контрактов, настройку и запуск компонентов и проведение интеграционных тестов.

## Обзор системы

Система состоит из трех основных компонентов:
1. **Смарт-контракты** (Solidity, Foundry)
   - `BondOracle.sol`: Контракт оракула, который хранит и обновляет цены облигаций
   - `BondFactory.sol`: Фабрика для создания токенов облигаций и их регистрации в оракуле
   - `BondToken.sol`: Токен облигации (ERC20)
   - `SoulBoundIdentityNFT.sol`: Токен идентификации пользователя

2. **OffchainPriceProvider** (Python, Flask)
   - Веб-сервер, который получает котировки ОФЗ с Московской биржи
   - Подписывает данные о ценах приватным ключом для последующей проверки в смарт-контракте
   - Кеширует ответы для уменьшения нагрузки на API биржи

3. **OnchainPricePublisher** (Python, Web3.py)
   - Сервис, который периодически получает цены из OffchainPriceProvider
   - Сравнивает полученные цены с текущими ценами в смарт-контракте
   - Отправляет транзакции для обновления цен, если изменение превышает заданный порог

## Быстрый старт

### Предварительные требования

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (включая `anvil`, `forge` и `cast`)
- Python 3.7+
- curl, jq (для тестовых скриптов)

### Настройка тестового окружения

1. Клонировать репозиторий и перейти в корневую директорию проекта:
   ```bash
   git clone <repo-url>
   cd <repo-directory>
   ```

2. Запустить скрипт настройки тестового окружения:
   ```bash
   ./misc/setup_test_environment.sh
   ```

   Этот скрипт выполнит следующие действия:
   - Запустит локальную блокчейн-ноду Anvil
   - Развернет смарт-контракты через скрипт Deploy.s.sol
   - Создаст тестовые облигации с заданными SECID (SU52005RMFS4, SU26240RMFS6, SU26241RMFS4)
   - Сгенерирует рабочие файлы .env для OffchainPriceProvider и OnchainPricePublisher с актуальными адресами контрактов
   - Создаст вспомогательный скрипт misc/issue_bond.sh для создания дополнительных облигаций

3. Запустить сервисы:
   - OffchainPriceProvider:
     ```bash
     cd backend/OffchainPriceProvider
     python3 app.py
     ```
   
   - OnchainPricePublisher:
     ```bash
     cd backend/OnchainPricePublisher
     python3 publisher.py
     ```

### Запуск интеграционных тестов

После настройки тестового окружения и запуска сервисов вы можете запустить интеграционные тесты:

```bash
./misc/run_integration_tests.sh
```

Этот скрипт проверит:
- Работу локальной блокчейн-ноды Anvil
- Доступность OffchainPriceProvider
- Наличие цен для тестовых облигаций в OffchainPriceProvider
- Регистрацию тестовых облигаций в BondOracle
- Функциональность OnchainPricePublisher по обновлению цен

## Ручные операции

### Создание новой облигации

Для создания новой облигации можно использовать сгенерированный скрипт:

```bash
./misc/issue_bond.sh [RPC_URL] [PRIVATE_KEY] [BOND_FACTORY_ADDRESS] [SECID] [INITIAL_PRICE] [MATURITY_PRICE] [MATURITY_TIME]
```

Пример:
```bash
./misc/issue_bond.sh http://127.0.0.1:8545 "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" "0xContractAddress" "SU12345RMFS6" "660050000" "700000000"
```

Скрипт `issue_bond.sh` генерируется автоматически при запуске `setup_test_environment.sh` и содержит адрес BondFactory, полученный при развёртывании контрактов.

### Проверка регистрации SECID в BondOracle

Для проверки регистрации SECID в контракте BondOracle:

```bash
cast call --rpc-url http://127.0.0.1:8545 \
  [BOND_ORACLE_ADDRESS] \
  "secidToBond(string)(address)" \
  "[SECID]"
```

Если возвращаемый адрес не равен нулевому адресу, SECID зарегистрирован.

### Получение текущей цены из BondOracle

Чтобы получить текущую цену облигации из BondOracle:

1. Сначала получите адрес токена облигации:
   ```bash
   cast call --rpc-url http://127.0.0.1:8545 \
     [BOND_ORACLE_ADDRESS] \
     "secidToBond(string)(address)" \
     "[SECID]"
   ```

2. Затем получите информацию о цене, используя адрес токена:
   ```bash
   cast call --rpc-url http://127.0.0.1:8545 \
     [BOND_ORACLE_ADDRESS] \
     "getPriceFeed(address)(uint160,uint40,uint40)" \
     "[BOND_TOKEN_ADDRESS]"
   ```

## Расширение и дополнительная настройка

### Настройка переменных окружения

Для настройки под собственными нуждами измените значения в файлах .env:

- **OffchainPriceProvider**:
  - `ETH_PRIVATE_KEY`: Приватный ключ для подписи цен
  - `CACHE_TTL`: Время кеширования данных в секундах
  - `PORT`: Порт для веб-сервера

- **OnchainPricePublisher**:
  - `ONCHAIN_PUBLISHER_BOND_ORACLE_ADDRESS`: Адрес контракта BondOracle
  - `ONCHAIN_PUBLISHER_ETHEREUM_RPC_URL`: URL для подключения к ноде Ethereum
  - `ONCHAIN_PUBLISHER_PRIVATE_KEY`: Приватный ключ для отправки транзакций
  - `ONCHAIN_PUBLISHER_POLL_INTERVAL_SECONDS`: Интервал обновления цен
  - `ONCHAIN_PUBLISHER_PRICE_CHANGE_THRESHOLD_PERCENT`: Порог изменения цены для обновления

### Подключение к тестовым или основным сетям

Для работы в тестовой или основной сети Ethereum:

1. Обновите `ONCHAIN_PUBLISHER_ETHEREUM_RPC_URL` в .env файле OnchainPricePublisher
2. Обновите `ONCHAIN_PUBLISHER_CHAIN_ID` в соответствии с сетью
3. Используйте приватные ключи с достаточным балансом для деплоя и транзакций
4. Разверните контракты в выбранной сети
