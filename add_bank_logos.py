#!/usr/bin/env python3
"""
Скрипт для добавления логотипов банков в Assets.xcassets
Использование:
1. Экспортируйте логотипы из Figma в папку 'bank_logos'
2. Запустите скрипт: python3 add_bank_logos.py
"""

import os
import shutil
import json
from pathlib import Path

# Маппинг названий файлов из Figma к именам в Assets
BANK_MAPPING = {
    'alataucitybank': 'Alatau City Bank',
    'halyk_bank': 'Halyk Bank',
    'kaspi': 'Kaspi',
    'Home_Credit': 'Home Credit Bank',
    'Eurasian': 'Eurasian Bank',
    'Forte': 'Forte Bank',
    'Otbasy': 'Otbasy Bank',
    'rbk': 'Bank RBK',
    'Center_Credit': 'Bank Center Credit',
    'Freedom': 'Freedom Bank',
    'Jusan': 'Jusan Bank',
    'tengri': 'Tengri Bank',
    'BRK': 'BRK Bank',
    'kaz_post': 'Qazpost Bank',
    'Altyn': 'Altyn Bank',
    'Nur_Bank': 'Nur Bank',
    'Bereke': 'Bereke Bank',
    'AsiaCredit': 'Asia Credit Bank',
    'ENPF': 'ENPF',
    'kzi': 'KZI Bank',
    'shinhan': 'Shinhan Bank',
    'KBO': 'KBO',
    'ATF': 'ATF Bank',
    'Placeholder': 'Placeholder',
    'koronapay': 'Korona Pay',
    'VisaPlus': 'Visa Plus',
    'tbank': 'T Bank',
    'Uzum': 'Uzum Bank',
    'onlinebank': 'Onlinebank',
    'alfa_bank': 'Alfa Bank',
    'sber': 'Sber Bank',
    'citi': 'City Bank',
    'VTB': 'VTB Bank',
    'EBR': 'EBR',
    'Bank_of_China': 'Bank of China',
    'Zaman': 'Zaman',
    'NAO_PDG': 'NAO PDG',
    'KCSD': 'KCSD',
    'KASE': 'KASE',
    'Hilal': 'Hilal Bank',
    'Moscow_Bank': 'Moscow Bank',
    'ICBC': 'ICBC',
    'Comitet_Kaznacheistva': 'Комитет Казначейства',
    'NBRK': 'NBRK'
}

def update_contents_json(asset_name, image_path_1x=None, image_path_2x=None, image_path_3x=None):
    """Обновляет Contents.json для asset с путями к изображениям"""
    asset_dir = Path(f'AIFinanceManager/Assets.xcassets/{asset_name}.imageset')
    contents_path = asset_dir / 'Contents.json'
    
    if not contents_path.exists():
        print(f"⚠️  {asset_name}: Contents.json не найден")
        return False
    
    with open(contents_path, 'r') as f:
        contents = json.load(f)
    
    # Обновляем пути к изображениям
    updated = False
    for image in contents['images']:
        scale = image.get('scale', '1x')
        if scale == '1x' and image_path_1x:
            image['filename'] = os.path.basename(image_path_1x)
            updated = True
        elif scale == '2x' and image_path_2x:
            image['filename'] = os.path.basename(image_path_2x)
            updated = True
        elif scale == '3x' and image_path_3x:
            image['filename'] = os.path.basename(image_path_3x)
            updated = True
    
    if updated:
        with open(contents_path, 'w') as f:
            json.dump(contents, f, indent=2)
        return True
    return False

def copy_image_to_asset(source_path, asset_name, scale='1x'):
    """Копирует изображение в asset директорию"""
    asset_dir = Path(f'AIFinanceManager/Assets.xcassets/{asset_name}.imageset')
    asset_dir.mkdir(parents=True, exist_ok=True)
    
    if scale == '1x':
        filename = f'{asset_name}.png'
    elif scale == '2x':
        filename = f'{asset_name}@2x.png'
    else:  # 3x
        filename = f'{asset_name}@3x.png'
    
    dest_path = asset_dir / filename
    
    if os.path.exists(source_path):
        shutil.copy2(source_path, dest_path)
        print(f"✅ Скопировано: {source_path} -> {dest_path}")
        return str(dest_path)
    else:
        print(f"⚠️  Файл не найден: {source_path}")
        return None

def main():
    """Основная функция"""
    print("=" * 60)
    print("Добавление логотипов банков в Assets.xcassets")
    print("=" * 60)
    print()
    print("Инструкция:")
    print("1. Экспортируйте логотипы из Figma в папку 'bank_logos'")
    print("2. Назовите файлы в формате: {bank_name}.png (например, alataucitybank.png)")
    print("3. Для @2x и @3x версий используйте: {bank_name}@2x.png и {bank_name}@3x.png")
    print()
    
    bank_logos_dir = Path('bank_logos')
    
    if not bank_logos_dir.exists():
        print(f"⚠️  Папка '{bank_logos_dir}' не найдена")
        print("Создайте папку и добавьте туда экспортированные логотипы из Figma")
        return
    
    # Обрабатываем каждый банк
    for asset_name, display_name in BANK_MAPPING.items():
        print(f"\n📦 Обработка: {display_name} ({asset_name})")
        
        # Ищем файлы для разных масштабов
        base_path = bank_logos_dir / asset_name
        path_1x = bank_logos_dir / f'{asset_name}.png'
        path_2x = bank_logos_dir / f'{asset_name}@2x.png'
        path_3x = bank_logos_dir / f'{asset_name}@3x.png'
        
        # Если есть базовый файл без суффикса, используем его для всех масштабов
        if base_path.with_suffix('.png').exists():
            path_1x = base_path.with_suffix('.png')
            if not path_2x.exists():
                path_2x = path_1x
            if not path_3x.exists():
                path_3x = path_1x
        
        # Копируем изображения
        copied_1x = copy_image_to_asset(path_1x, asset_name, '1x') if path_1x.exists() else None
        copied_2x = copy_image_to_asset(path_2x, asset_name, '2x') if path_2x.exists() else None
        copied_3x = copy_image_to_asset(path_3x, asset_name, '3x') if path_3x.exists() else None
        
        # Обновляем Contents.json
        if copied_1x or copied_2x or copied_3x:
            update_contents_json(asset_name, copied_1x, copied_2x, copied_3x)
            print(f"✅ {display_name} добавлен")
        else:
            print(f"⚠️  {display_name}: изображения не найдены")
    
    print()
    print("=" * 60)
    print("Готово! Проверьте Assets.xcassets в Xcode")
    print("=" * 60)

if __name__ == '__main__':
    main()
