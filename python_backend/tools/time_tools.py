import datetime
import cnlunar
from config.config_manager import config
import pytz

# num为数字，返回num的中文大写表示
def num_to_cn(num, is_lunar=False):
    num = int(num)
    if num == 0:
        return '日' if is_lunar else '零'
    elif num < 0:
        return '负' + num_to_cn(abs(num))
    elif num < 10:
        return ['', '一', '二', '三', '四', '五', '六', '七', '八', '九'][num]
    elif num < 100:
        return num_to_cn(num // 10) + '十' + num_to_cn(num % 10)
    elif num < 1000:
        return num_to_cn(num // 100) + '百' + num_to_cn(num % 100)
    elif num < 10000:
        return num_to_cn(num // 1000) + '千' + num_to_cn(num % 1000)
    else:
        return num_to_cn(num // 10000) + '万' + num_to_cn(num % 10000)

# 返回当前日期、时间，和农历日期的字符串
def get_lunar_cn():
    now = datetime.datetime.now()
    lunar = cnlunar.Lunar(now, godType='8char')
    month_cn = lunar.lunarMonthCn
    month_cn = month_cn.replace('小', '').replace('大', '')
    return now.strftime('%Y-%m-%d %H:%M:%S') + '，星期' + num_to_cn(now.strftime('%w'), is_lunar=True) +', 农历' +  month_cn + lunar.lunarDayCn

def get_time_and_location_cn() -> str:
    return f"当前地点是:%s， 时间：%s。 " % (config.llm.get('location'),  get_lunar_cn())

# Returns current date, time, and lunar calendar date as a string in English
def get_lunar_en():
    now = datetime.datetime.now()
    lunar = cnlunar.Lunar(now, godType='8char')
    month = lunar.lunarMonth
    return now.strftime('%Y-%m-%d %H:%M:%S') + f', {now.strftime("%a")}' + f', Moon {month}/{lunar.lunarDay}'

def get_time_and_location_en() -> str:
    return f"Current location: %s, Time: %s. " % (config.llm.get('location'), get_lunar_en())

def get_local_time_str(timezone_str: str = 'Asia/Shanghai') -> str:
    # timezone: Asia/Shanghai , return format: 2024-11-17 12:20:08 Monday, Moon 10/17
    if timezone_str not in pytz.all_timezones:
        timezone_str = 'Asia/Shanghai'
    timezone = pytz.timezone(timezone_str)
    now = datetime.datetime.now(timezone)
    lunar = cnlunar.Lunar(datetime.datetime.now(), godType='8char')
    return now.strftime('%Y-%m-%d %H:%M:%S %a') + f', Moon {lunar.lunarMonth}/{lunar.lunarDay}'

if __name__ == '__main__':
# 当前地点是: ..， 时间：2024-11-17 12:20:08，星期日, 农历十月十七。 
# Current location: .., Time: 2024-11-17 12:20:08, Sun, Moon 10/17. 
    print(get_time_and_location_cn())
    print(get_time_and_location_en())
    print(get_local_time_str())
