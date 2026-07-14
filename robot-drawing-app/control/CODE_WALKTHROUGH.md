# gcode_to_mycobot.py — 코드 전체 설명

MyCobot 280 로봇팔을 실제로 움직여서 gcode(`.nc`) 파일에 적힌 도형을 그리게
만드는 스크립트입니다. `robot-drawing-app/control/gcode_to_mycobot.py`에 있고,
`vision/photo_to_robot_path.py`가 만들어내는 `optional_gcode.txt` 같은
G-code 스타일 파일(또는 `square.nc`처럼 직접 준비한 gcode 파일)을 입력으로
받아서, 로봇팔의 실제 XYZ 좌표 이동 명령으로 바꿔 전송합니다.

**전체 그림**: 로봇팔에 시리얼로 연결 → 팔을 정해진 시작 자세로 이동시키고
그 지점의 좌표를 기준값으로 저장 → 사용자가 어떤 도형을 그릴지 번호로 선택
→ 해당 gcode 파일을 한 줄씩 읽어서 X/Y/Z 좌표 리스트로 변환(`process_gcode`)
→ 좌표를 하나씩 순서대로 로봇팔에 보내면서 이동이 끝날 때까지 대기. 아직
사각형(1번)만 "파싱 + 실제 전송"까지 완성되어 있고, 삼각형(2번)은 파싱만
되어 있으며 별(3)·원(4)·미소(5)·종료(6) 분기는 아직 코드가 없는
미완성 상태입니다.

---

## 1. 라이브러리 불러오기 & 로봇팔 연결/초기화

`pymycobot` 라이브러리로 실제 하드웨어(MyCobot 280)와 시리얼 통신을 엽니다.
`'COM5'`는 윈도우 PC에서 로봇팔이 잡힌 포트 번호이고(리눅스라면 주석 처리된
`/dev/ttyUSB0` 줄을 대신 씁니다), 두 번째 인자 `115200`은 통신 속도(baud
rate)로 로봇팔 펌웨어와 반드시 맞아야 하는 고정값입니다.

`set_fresh_mode(0)`은 로봇팔의 보간(interpolation) 모드를 설정하는
부분으로, 이동 명령을 받을 때마다 즉시 그 자세로 스냅하듯 움직일지, 부드럽게
경로를 보간해서 움직일지를 정합니다. 그다음 `send_angles`로 6개 관절
각도를 지정해서 팔을 "펜 끝이 아래를 향한" 그리기 시작 자세로 보내고,
`time.sleep(2)`로 실제로 그 자세까지 물리적으로 이동할 시간을 벌어줍니다
(로봇팔은 명령을 비동기로 받기 때문에, 이동이 끝나길 기다리지 않고 다음
명령을 보내면 중간 자세에서 좌표를 잘못 읽거나 다음 명령과 겹쳐 버립니다).

이동이 끝난 뒤 `get_coords()`로 그 시작 자세의 실제 XYZ + 자세각(rx, ry,
rz)을 읽어두는데, 이 값의 rx/ry/rz 세 개는 뒤에서 `process_gcode`가 모든
그리기 좌표에 그대로 재사용합니다 — gcode 파일 자체에는 팔의 회전 자세
정보가 없기 때문에, "펜이 항상 아래를 향한 채로 평면 위 XY만 움직인다"는
전제를 이 시작 자세의 각도로 고정해 두는 것입니다.

```python
# import library
import time
from pymycobot.mycobot280 import MyCobot280  # import mycobot library,if don't have, first 'pip install pymycobot'

# use PC and M5 control
mc = MyCobot280('COM5', 115200)  # WINDOWS use ，need check port number when you PC
# mc = MyCobot('/dev/ttyUSB0',115200)           # VM linux use
time.sleep(0.5)

# Set interpolation mode
mc.set_fresh_mode(0)
time.sleep(0.5)
# Send the initial point angle of the robot arm, the speed is 50,
# it can be customized and modified, as long as the end is facing down
mc.send_angles([3, 5.3, -96.8, 8, -1.2, -69.7], 50)
# Wait 2 seconds for the robot arm to move to the specified angle
time.sleep(2)
# Get the current coordinates of the robot arm
get_coords = mc.get_coords()
time.sleep(1)
```

## 2. 전역 변수 — 좌표 저장소와 그리기 속도

`data_coords`는 `process_gcode`가 파싱한 좌표들을 계속 쌓아두는 리스트입니다
(함수 안에서 만들지 않고 전역에 둔 이유는, 나중에 같은 세션에서 여러 도형을
연달아 그릴 때도 지금까지 그린 좌표 기록을 한 리스트에 계속 모아두려는
의도로 보입니다). `draw_speed`는 로봇팔이 좌표 사이를 이동할 때의 속도값으로,
0~100 범위이며 너무 빠르면 그림이 흔들리고 너무 느리면 한 도형 그리는 데
오래 걸립니다.

```python
# Save the parsed coordinates
data_coords = []
# Set the drawing speed to 100, and the speed range is 0~100
draw_speed = 70
```

## 3. `process_gcode` — gcode 파일을 좌표 리스트로 변환

이 함수가 이 스크립트의 핵심 파싱 로직입니다. gcode 파일을 한 줄씩 읽으면서,
`G0`(펜 든 채 이동) 또는 `G1`(그리면서 이동)로 시작하는 줄만 처리합니다.

각 줄은 `G1 X10 Y20` 처럼 공백으로 구분된 토큰들로 되어 있는데, 첫 토큰(G0/G1
자체)을 건너뛰고 나머지 토큰들을 보면서 `X`/`Y`/`Z`로 시작하는 부분의 숫자를
뽑아 각각 `coords[0]`, `coords[1]`, `coords[2]`에 채워 넣습니다. 대소문자를
둘 다 받아주는 이유는 gcode 생성기마다 소문자 좌표를 쓰는 경우도 있기
때문입니다.

여기서 중요한 트릭은 **"gcode 한 줄에 X/Y/Z 값이 다 안 적혀 있을 수도
있다"**는 gcode 포맷의 특성을 처리하는 부분입니다. gcode는 보통 이전 줄과
값이 같은 축은 생략합니다(예: `G1 X10 Y20` 다음 줄이 `G1 X15`면 Y는 그대로
20). 그래서 매 줄마다 `last_coords`를 복사해서 시작하고, 실제로 그 줄에서
읽은 값만 덮어씁니다. 다만 이 스크립트는 "값이 0.0이면 생략된 것"으로
판단하는 방식을 쓰기 때문에, 만약 실제 gcode에 진짜 좌표 0을 의도한 줄이
있다면 그 값도 "생략됨"으로 오인해서 이전 좌표를 대신 넣어버리는 한계가
있습니다 — 원점을 지나는 도형을 그릴 계획이라면 주의가 필요합니다.

자세각(rx, ry, rz)은 이 함수 안에서 한 번도 다시 계산되지 않고, 맨 처음
`get_coords`에서 읽어온 시작 자세 값이 모든 좌표에 그대로 유지됩니다(펜이
계속 같은 각도로 아래를 향한 채 평면 위만 움직인다는 전제).

```python
def process_gcode(file_path):
    """
    Parse the contents of the gcode file, extract the XYZ coordinate values, and save the coordinate data into a list
    :param file_path: Gcode file path
    :return: A coordinate list
    """
    # The last valid coordinate, using the rx, ry, rz values
    # in the current coordinates of the robot arm as the starting attitude
    last_coords = [0.0, 0.0, 0.0, get_coords[3], get_coords[4], get_coords[5]]
    with open(file_path, 'r') as file:
        # Line-by-line processing instructions
        for line in file:
            command = line.strip()  # Remove newline characters and other whitespace characters at the end of the line
            if command.startswith("G0") or command.startswith("G1"):  # Move command
                coords = last_coords[:]  # Copy the previous valid coordinates
                command_parts = command.split()
                for part in command_parts[1:]:
                    if part.startswith("X") or part.startswith("x"):
                        coords[0] = float(part[1:])  # Extract and transform X coordinate data
                    elif part.startswith("Y") or part.startswith("y"):
                        coords[1] = float(part[1:])  # Extract and transform Y coordinate data
                    elif part.startswith("Z") or part.startswith("z"):
                        coords[2] = float(part[1:])  # Extract and transform Z coordinate data
                if coords[0] == 0.0 and coords[1] == 0.0:  # If XY data is missing, use the last valid XY coordinates
                    coords[0] = last_coords[0]
                    coords[1] = last_coords[1]
                if coords[2] == 0.0:  # If Z data is missing, use the last valid Z coordinate
                    coords[2] = last_coords[2]
                last_coords = coords
                data_coords.append(coords)  # Add coordinates to list and save
    return data_coords
```

## 4. 메인 실행부 — 도형 선택 후 그리기

사용자에게 1~6번 중 그릴 도형(또는 종료)을 입력받습니다. 1번(사각형)을
고르면 `square.nc` 파일을 `process_gcode`로 파싱한 뒤, 나온 좌표를 하나씩
`mc.send_coords(i, draw_speed, 1)`로 로봇팔에 전송합니다 — 세 번째 인자
`1`은 좌표 이동 모드(직선 보간)를 뜻합니다. 좌표 하나를 보낼 때마다
`time.sleep(1)`로 1초씩 기다리는 이유는, `send_coords`가 로봇팔에 명령만
비동기로 보내고 바로 반환하기 때문입니다 — 실제 이동이 끝나기 전에 다음
좌표를 보내버리면 로봇팔이 각 점을 다 들르지 않고 명령을 건너뛰거나 경로가
뭉개질 수 있어서, 매 이동마다 도착할 시간을 강제로 확보해 주는 것입니다.

2번(삼각형)은 아직 `triangle.nc`를 읽어 좌표로 바꾸는 부분까지만 있고,
1번처럼 좌표를 실제로 로봇팔에 보내는 `for` 루프가 빠져 있습니다. 3~6번
(별·원·미소·종료) 분기는 안내 문구에만 있고 실제 처리 코드는 아직
작성되지 않았습니다.

```python
type = int(input('Please input 1-6（1-square 2-triangle 3-star 4-circle 5-smile 6-quit）:'))
if type == 1:
    # Pass in the gcode file path and obtain the coordinate data
    # File path can be customized
    coords_data = process_gcode('square.nc')
    # Send coordinates to the robot arm one by one
    for i in coords_data:
        mc.send_coords(i, draw_speed, 1)  # Send coordinates to the robot arm
        time.sleep(1)  # Wait 1 second for the robot arm movement to complete
elif type == 2:
    coords_data = process_gcode('triangle.nc')
```

## 마무리

**로봇팔을 시작 자세로 이동시키며 기준 자세각을 저장하고(`get_coords`) →
사용자가 고른 gcode 파일을 `process_gcode`가 한 줄씩 읽어 X/Y/Z만 채우고
자세각은 기준값을 그대로 붙여 좌표 리스트로 바꾼 뒤 → 메인 실행부가 그
좌표들을 한 점씩 `mc.send_coords`로 전송하고 매번 1초씩 기다려 실제
움직임이 끝나길 확인하는 흐름**이며, 지금은 1번(사각형) 분기만 파싱부터
전송까지 완성되어 있고 2번(삼각형)은 파싱만, 3~6번은 아직 미구현입니다.
