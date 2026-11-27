# TWILIGHT private resource packs

비공개 리소스팩 전달용. 원본 리소스는 이 저장소 릴리스에만 둡니다.

## 시작 데이터 준비

`tools/prepare_startup_bakes.py`는 기존 원본 팩과 해당 빌드의 전체 Android
내보내기 리소스 팩(PCK)으로 실제 게임을 임시 프로필에서 실행합니다. 게임이
직접 만든 검증된 아이템·장비·지도 등의 캐시를 설치용 시작 데이터 ZIP으로
구성합니다. 원본 팩, 사용자 저장 및 프로필은 ZIP에 포함되지 않습니다.

```sh
python3 tools/prepare_startup_bakes.py \
  --game /local/TWILIGHT --original /local/source523 \
  --game-pack /local/android-full.pck --game-pack-sha256 <sha256> \
  --godot /local/godot-4.7.2 --output /local/new-startup-build
```

준비에는 설치한 시작 데이터가 없는 원본 팩 디렉터리를 사용합니다.
전체 PCK는 Android 프리셋의 `--export-pack`으로 생성합니다. 준비 결과는 지정한
로컬 경로에만 저장됩니다. `private-pack/startup_bake_pin.json`은 별도 검토 후
같은 게임 코드의 프로젝트 루트에 추가하고, 같은 내보내기로 키 호환성을
재검사합니다. 달라진 키, 없거나 손상된 데이터는 게임의 원본 검증으로 돌아갑니다.
