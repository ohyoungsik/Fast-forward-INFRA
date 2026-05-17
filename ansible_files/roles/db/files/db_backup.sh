#!/bin/bash
set -e 

# ========== 에러 로그 캡처 설정 ==========
ERROR_LOG="/tmp/backup_error.log"
> $ERROR_LOG
exec 2> >(tee -a $ERROR_LOG >&2)

export AWS_DEFAULT_REGION="ap-northeast-2"

# s3_env.sh 파일을 불러와서 $BUCKET_NAME 변수를 저장
if [ -f /root/s3_env.sh ]; then
    source /root/s3_env.sh
fi

TIMESTAMP=$(TZ='Asia/Seoul' date +%Y%m%d_%H%M%S)

# mktemp으로 예측 불가능한 안전한 임시 파일 생성
BACKUP_PATH=$(mktemp /tmp/db_backup_${TIMESTAMP}_XXXXXX.dump)

DB_HOST="172.16.20.30"

# ========== 알림 발송 함수 ==========
send_alert() {
    local BOT_TOKEN="8674034190:AAE4a9EsNsaozYtYTbvFIqJ7FerxMwmWb3g"
    local CHAT_ID="8722599561"
    
    local ERROR_DETAIL=$(tail -n 3 $ERROR_LOG)
    
    local MESSAGE="🚨 [긴급] DB 백업 실패!

- 발생 시간: $(date +'%Y-%m-%d %H:%M:%S')
- 대상 서버: $DB_HOST ($DB_NAME)
- 사용 버킷: $BUCKET_NAME
- 상세 에러 내용:
${ERROR_DETAIL}"

    echo "▶️ 텔레그램으로 알림을 전송하는 중..."
    
    local RESPONSE=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        -d parse_mode="HTML" \
        -d text="${MESSAGE}")

    if echo "$RESPONSE" | grep -q '"ok":true'; then
        echo "✅ 텔레그램 알림 전송 성공!"
    else
        echo "❌ 텔레그램 알림 전송 실패!"
        echo "👉 상세 원인: $RESPONSE"
    fi 
}

# set -e 환경에서 안정적인 ERR 트랩 사용
trap 'send_alert' ERR

# ========== 실제 백업 작업 ==========
echo "------------------------------------------"
echo "[$(date)] 백업 작업을 시작합니다."
echo "✅ 대상 S3 버킷: $BUCKET_NAME"

# 1. DB 추출
# pg_dump가 실패하면 바로 trap 'send_alert' ERR이 작동합니다 (if문 밖이라서)
pg_dump -h $DB_HOST -U $DB_USER -d $DB_NAME -F c -f $BACKUP_PATH
echo "✅ DB 추출 성공: $BACKUP_PATH"

# 2. S3 업로드 (if문 안이므로 에러 시 직접 알림 호출)
if aws s3 cp $BACKUP_PATH s3://$BUCKET_NAME/; then
    echo "✅ S3 업로드 완료!"
    rm -f $BACKUP_PATH
    echo "✅ 서버 로컬 임시 파일 삭제 완료!"
else
    echo "❌ S3 업로드 실패 - 로컬 파일 보존: $BACKUP_PATH"
    # 여기에 직접 알림 함수를 추가합니다.
    send_alert
    exit 1
fi

echo "------------------------------------------"