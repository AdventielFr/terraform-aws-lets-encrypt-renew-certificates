import json
import boto3
import os
import logging
from datetime import datetime, timedelta
import pytz

logger = logging.getLogger('test')
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    requests = _find_expired_certificate_renew_requests()
    for request in requests:
        _send_request_to_refresh_certificate(request)
        
def _send_request_to_refresh_certificate(request):
    client = boto3.client('sqs')
    client.send_message(
        QueueUrl = os.environ['SQS_URL'],
        MessageBody = json.dumps(request)
    ) 

def _is_expired(certificate):
    logger.info(certificate)
    issuer = certificate['Issuer']
    if issuer != 'Let\'s Encrypt':
        return False
    logger.info(certificate['NotAfter'])
    limit = certificate['NotAfter'] - timedelta( days = 5)
    now = pytz.utc.localize(datetime.utcnow())
    return now >= limit

def _find_expired_certificate_renew_requests():
    logger.info('find expired certificates ...')
    result = []
    client = boto3.client('acm')
    response = client.list_certificates()
    if 'CertificateSummaryList' in response:
        for item in response['CertificateSummaryList']:
            response = client.describe_certificate(CertificateArn = item['CertificateArn'])
            if _is_expired(response['Certificate']):
                logger.info(response)
                response = client.list_tags_for_certificate(CertificateArn = item['CertificateArn'])
                logger.info(response)
                emailTag = next((x for x in response['Tags'] if x['Key'] == 'Email'), None)
                logger.info(emailTag)
                certificate_renew_request = {}
                certificate_renew_request['domain'] = item['DomainName']
                certificate_renew_request['email'] = emailTag['Value']
                result.append(certificate_renew_request)
    return result