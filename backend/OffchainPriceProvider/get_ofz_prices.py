import datetime as dt
import time 
import requests 
import pandas as pd

BASE = "https://iss.moex.com/iss/engines/stock/markets/bonds"
SECURITIES_BASE = "https://iss.moex.com/iss/securities"
HEAD = {"User-Agent": "ofz-price-bot/1.0"}

def fetch_ofz_list(limit=10000):
    url = f"{BASE}/boards/TQOB/securities.json?iss.meta=off&limit={limit}"
    js = requests.get(url, headers=HEAD, timeout=15).json()
    df = pd.DataFrame(js["securities"]["data"],
                      columns=js["securities"]["columns"])
    return df[(df["SECTYPE"] == "3") & (df["STATUS"] == "A")][["SECID", "SHORTNAME"]]

def market_prices(secid):
    """
    Get market prices for a given security, prioritizing different price fields
    in the following order: MARKETPRICE, LAST, LCLOSEPRICE, WAPRICE, PREVWAPRICE
    
    Args:
        secid (str): Security ID
        
    Returns:
        tuple: (price, source_field) - price is the best available price,
               source_field is the name of the field from which the price was taken
    """
    url = f"{BASE}/securities/{secid}.json?iss.only=marketdata&iss.meta=off"
    js = requests.get(url, headers=HEAD, timeout=10).json()["marketdata"]
    cols, data = js["columns"], js["data"][0]
    
    # Create dictionary of all price fields
    price_data = {
        field: data[cols.index(field)] if field in cols else None
        for field in ["MARKETPRICE", "LAST", "LCLOSEPRICE", "WAPRICE", "PREVWAPRICE", "CLOSEPRICE"]
    }
    
    # Try to get price in order of priority
    for field in ["MARKETPRICE", "LAST", "LCLOSEPRICE", "WAPRICE", "PREVWAPRICE", "CLOSEPRICE"]:
        if price_data.get(field) is not None:
            return price_data[field], field
    
    return None, None

def daily_candles(secid, date_from, date_to):
    url = (f"{BASE}/boards/TQOB/securities/{secid}/candles.json"
           f"?interval=24&from={date_from}&to={date_to}&iss.meta=off")
    js = requests.get(url, headers=HEAD, timeout=10).json()["candles"]
    df = pd.DataFrame(js["data"], columns=js["columns"])
    return df[["begin", "close"]]

def get_bond_details(secid):
    """
    Get detailed bond information from MOEX API.
    
    Args:
        secid (str): Security ID of the OFZ bond
        
    Returns:
        dict: Dictionary containing complete bond details
    """
    # Initialize details dictionary
    details = {
        # Core fields
        "initialPrice": None,     # Initial face value (nominal)
        "maturityPrice": None,    # Face value at maturity (nominal)
        "maturityAt": None,       # Maturity date
        "issueDate": None,        # Issue date
        "faceUnit": None,         # Currency of face value
        
        # Coupon fields
        "couponValue": None,      # Coupon value in currency units
        "couponPercent": None,    # Coupon rate as percentage
        "nextCoupon": None,       # Next coupon payment date
        "couponFrequency": None,  # Coupon payments per year
        "accruedInt": None,       # Accrued interest (НКД)
        
        # Additional fields
        "securityType": None,     # Security type (e.g., OFZ-PD)
        "issueSize": None,        # Issue volume
        "isin": None,             # ISIN code
        "regNumber": None,        # Registration number
    }
    
    # Use securities endpoint which has most of the information we need
    url = f"{SECURITIES_BASE}/{secid}.json?iss.only=securities,description&iss.meta=off"
    try:
        response = requests.get(url, headers=HEAD, timeout=15).json()
        
        # Process the description data (this contains many bond parameters)
        if "description" in response and response["description"]["data"]:
            desc_df = pd.DataFrame(response["description"]["data"], 
                                  columns=response["description"]["columns"])
            
            # Map MOEX field names to our field names
            field_mapping = {
                "INITIALFACEVALUE": "initialPrice",
                "FACEVALUE": "maturityPrice",
                "MATDATE": "maturityAt",
                "ISSUEDATE": "issueDate",
                "FACEUNIT": "faceUnit",
                "COUPONVALUE": "couponValue",
                "COUPONPERCENT": "couponPercent",
                "NEXTCOUPON": "nextCoupon",
                "COUPONFREQUENCY": "couponFrequency",
                "ACCRUEDINT": "accruedInt",
                "SECNAME": "securityType",
                "ISSUESIZE": "issueSize",
                "ISIN": "isin",
                "REGNUMBER": "regNumber"
            }
            
            # Extract each field from description
            for moex_field, our_field in field_mapping.items():
                field_row = desc_df[desc_df["name"] == moex_field]
                if not field_row.empty:
                    try:
                        # Try to convert numeric values to float
                        value = field_row.iloc[0]["value"]
                        if isinstance(value, str) and value.replace('.', '', 1).isdigit():
                            value = float(value)
                        details[our_field] = value
                    except (ValueError, TypeError):
                        details[our_field] = field_row.iloc[0]["value"]
            
            # If coupon frequency is given as period in days, convert to annual frequency
            if "COUPONPERIOD" in desc_df["name"].values:
                period_row = desc_df[desc_df["name"] == "COUPONPERIOD"]
                if not period_row.empty:
                    try:
                        period_days = float(period_row.iloc[0]["value"])
                        if period_days > 0:
                            details["couponFrequency"] = round(365 / period_days)
                    except (ValueError, TypeError, ZeroDivisionError):
                        pass
            
        # Some securities info might be missing from description, try the securities block
        if "securities" in response and response["securities"]["data"]:
            sec_df = pd.DataFrame(response["securities"]["data"],
                                 columns=response["securities"]["columns"])
            
            if not sec_df.empty:
                sec_dict = sec_df.iloc[0].to_dict()
                
                # Fill in any missing values from securities block
                if details["maturityPrice"] is None and "FACEVALUE" in sec_dict:
                    details["maturityPrice"] = sec_dict["FACEVALUE"]
                
                if details["maturityAt"] is None and "MATDATE" in sec_dict:
                    details["maturityAt"] = sec_dict["MATDATE"]
                
                if details["couponValue"] is None and "COUPONVALUE" in sec_dict:
                    details["couponValue"] = sec_dict["COUPONVALUE"]
                
                if details["couponPercent"] is None and "COUPONPERCENT" in sec_dict:
                    details["couponPercent"] = sec_dict["COUPONPERCENT"]
                
                if details["nextCoupon"] is None and "NEXTCOUPON" in sec_dict:
                    details["nextCoupon"] = sec_dict["NEXTCOUPON"]
        
        # If initialPrice is still None but maturityPrice is set, use maturityPrice as fallback
        if details["initialPrice"] is None and details["maturityPrice"] is not None:
            details["initialPrice"] = details["maturityPrice"]
            
    except Exception as e:
        print(f"Error fetching bond details for {secid}: {e}")
    
    return details

def get_price_detailed(secid):
    """
    Get detailed price information for a specific OFZ bond.
    
    Args:
        secid (str): Security ID of the OFZ bond
        
    Returns:
        dict: Dictionary containing detailed price information:
              - price: absolute price value (nominal * percentage/100)
              - price_percentage: percentage of nominal value (original price from MOEX)
              - priceSource: source of the price data (API field name or "candle")
              - nominal: nominal value of the bond
    """
    # Get bond details to retrieve the nominal value
    bond_details = get_bond_details(secid)
    nominal = bond_details.get("initialPrice")
    
    # Default to 100 if nominal value is not available
    if nominal is None or nominal <= 0:
        nominal = 100.0
    
    # Create result dictionary with price information
    result = {
        "price": None,
        "price_percentage": None,
        "priceSource": None,
        "nominal": nominal
    }
    
    # First try to get current market price
    price_percentage, price_source = market_prices(secid)
    
    if price_percentage is not None:
        # Calculate absolute price based on percentage of nominal
        absolute_price = (float(price_percentage) * nominal) / 100.0
        
        result["price"] = absolute_price
        result["price_percentage"] = float(price_percentage)
        result["priceSource"] = price_source
        return result
    
    # If current market price is not available, fall back to the most recent candle
    today = dt.date.today()
    week_ago = (today - dt.timedelta(days=7)).isoformat()
    
    candles = daily_candles(secid, week_ago, today.isoformat())
    
    if not candles.empty:
        # Get the most recent close price from candles (last row)
        price_percentage = float(candles.iloc[-1]['close'])
        absolute_price = (price_percentage * nominal) / 100.0
        
        result["price"] = absolute_price
        result["price_percentage"] = price_percentage
        result["priceSource"] = "candle"
        return result
    
    # If no data available from either source
    return result

def get_price(secid):
    """
    Get the price for a specific OFZ bond, falling back to daily candle data if market price is not available.
    This function maintains backward compatibility with existing API.
    
    Args:
        secid (str): Security ID of the OFZ bond
        
    Returns:
        tuple: (price, is_current_market_data) - price is the current or most recent price,
               is_current_market_data is True if the price is from current market data, False if from candle
    """
    # Use the detailed function internally
    price_info = get_price_detailed(secid)
    
    # Return the absolute price value and current market data flag
    # The price_info["price"] is already the absolute value calculated in get_price_detailed()
    price = price_info.get("price")
    is_current = price_info.get("priceSource") != "candle" if price is not None else False
    
    return price, is_current

def get_ofz_info(secid):
    """
    Get both price and bond details in a single convenient function.
    This is a helper function that combines get_price() and get_bond_details().
    
    Args:
        secid (str): Security ID of the OFZ bond
        
    Returns:
        dict: Dictionary containing both price and bond details
    """
    # Get price information (tuple format)
    price, is_current = get_price(secid)
    price_detail = get_price_detailed(secid)
    
    # Get bond details
    bond_details = get_bond_details(secid)
    
    # Create result dictionary
    result = {
        "price": price,  # Absolute price value
        "price_percentage": price_detail.get("price_percentage"),  # Price as percentage of nominal
        "nominal": price_detail.get("nominal"),  # Nominal value of the bond
        "is_current_market_data": is_current,
        "priceSource": price_detail["priceSource"]
    }
    
    # Add bond details
    result.update(bond_details)
    
    return result

if __name__ == "__main__":
    ofz = fetch_ofz_list()
    print(f"Найдено ОФЗ: {len(ofz)}")
    codes = ofz["SECID"].tolist()

    today = dt.date.today().isoformat()
    price_rows = []
    for code in codes[:3]:   # Только первые 3 для примера
        try:
            price, source = market_prices(code)
            price_rows.append((code, price, source))
            time.sleep(0.2)
        except Exception as err:
            print(code, "ошибка:", err)

    prices = pd.DataFrame(price_rows, columns=["SECID", "PRICE", "SOURCE"])
    print("\n=== Текущие котировки ===")
    print(prices)

    # Пример использования обновленных функций
    if codes:
        example_code = codes[-1]
        
        # 1. Получение только цены
        print(f"\n=== Только цена для {example_code} ===")
        price, is_current = get_price(example_code)
        price_detail = get_price_detailed(example_code)
        print(f"Абсолютная цена: {price}")
        print(f"Процент от номинала: {price_detail.get('price_percentage')}%")
        print(f"Номинал: {price_detail.get('nominal')}")
        print(f"Текущие данные рынка: {is_current}")
        print(f"Источник цены (подробно): {price_detail['priceSource']}")
        
        # 2. Получение только деталей облигации
        print(f"\n=== Только детали облигации для {example_code} ===")
        bond_details = get_bond_details(example_code)
        print(f"Начальная цена (номинал): {bond_details['initialPrice']}")
        print(f"Цена погашения (номинал): {bond_details['maturityPrice']}")
        print(f"Дата погашения: {bond_details['maturityAt']}")
        print(f"Дата выпуска: {bond_details['issueDate']}")
        print(f"Валюта номинала: {bond_details['faceUnit']}")
        print(f"Объем выпуска: {bond_details['issueSize']}")
        print(f"Частота выплаты купона (раз в год): {bond_details['couponFrequency']}")
        print(f"Купон (%): {bond_details['couponPercent']}")
        print(f"Сумма купона: {bond_details['couponValue']}")
        print(f"Следующий купон: {bond_details['nextCoupon']}")
        print(f"Тип ценной бумаги: {bond_details['securityType']}")
        print(f"Накопленный купонный доход (НКД): {bond_details['accruedInt']}")
        
        # 3. Получение полной информации (и цены, и деталей)
        print(f"\n=== Полная информация для {example_code} ===")
        full_info = get_ofz_info(example_code)
        print(f"Абсолютная цена: {full_info['price']}")
        print(f"Процент от номинала: {full_info['price_percentage']}%")
        print(f"Номинал: {full_info['nominal']}")
        print(f"Источник цены: {full_info['priceSource']}")
        print(f"Текущие данные рынка: {full_info['is_current_market_data']}")
        print(f"Начальная цена (номинал): {full_info['initialPrice']}")
        print(f"Цена погашения (номинал): {full_info['maturityPrice']}")
        print(f"Дата погашения: {full_info['maturityAt']}")
        print(f"ISIN: {full_info['isin']}")
        print(f"Регистрационный номер: {full_info['regNumber']}")

    # Проверка для ОФЗ из примера (SU26207RMFS9)
    if "SU26207RMFS9" in codes:
        # Получаем полную информацию
        su26207_info = get_ofz_info("SU26207RMFS9")
        print(f"\n=== Информация для SU26207RMFS9 (пример с Мосбиржи) ===")
        print(f"Абсолютная цена: {su26207_info['price']}")
        print(f"Процент от номинала: {su26207_info['price_percentage']}%")
        print(f"Номинал: {su26207_info['nominal']}")
        print(f"Источник цены: {su26207_info['priceSource']}")
        print(f"Текущие данные рынка: {su26207_info['is_current_market_data']}")
        print(f"Начальная цена (номинал): {su26207_info['initialPrice']}")
        print(f"Цена погашения (номинал): {su26207_info['maturityPrice']}")
        print(f"Дата погашения: {su26207_info['maturityAt']}")
