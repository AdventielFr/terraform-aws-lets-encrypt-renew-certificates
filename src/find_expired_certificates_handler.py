import json
import boto3
import os
import logging
from datetime import datetime, timedelta
import pytz

logger = logging.getLogger('adv_lambda')
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    try:
        requests = _find_expired_certificate_renew_requests()
        logger.info('{} certificat(s) to refresh'.format(len(requests)))
        for request in requests:
            _send_request_to_refresh_certificate(request)
    except Exception as e:
        logger.error(e)
        _send_message("Fail to renew certificates from let's and script reason: {}".format(e))

def _send_request_to_refresh_certificate(request):
    logger.info('application for renewal of certificate {} ({}) ...'.format(request['domain'], request['email']))
    client = boto3.client('sqs')
    client.send_message(
        QueueUrl = os.environ['SQS_REQUEST_URL'],
        MessageBody = json.dumps(request)
    ) 

def _is_expired(certificate):
    issuer = certificate['Issuer']
    if issuer != 'Let\'s Encrypt':
        return False
    limit = certificate['NotAfter'] - timedelta(days = int(os.environ['NB_DAYS_BEFORE_EXPIRATION']))
    now = pytz.utc.localize(datetime.utcnow())
    logger.info('cerficate         : {}'.format(certificate['DomainName']))
    logger.info('   not after date : {}'.format(certificate['NotAfter']))
    logger.info('   limit date     : {}'.format(limit))
    logger.info('   now date     : {}'.format(now))
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
                response = client.list_tags_for_certificate(CertificateArn = item['CertificateArn'])
                emailTag = next((x for x in response['Tags'] if x['Key'] == 'Email'), None)
                certificate_renew_request = {}
                certificate_renew_request['domain'] = item['DomainName']
                certificate_renew_request['email'] = emailTag['Value']
                certificate_renew_request['custom_args'] = []
                certificate_renew_request['custom_args'].append('--force-renewal')
                result.append(certificate_renew_request)
    return result

def _send_message(message):
    logger.info('Send result message ....')
    sns = boto3.client('sns')
    return sns.publish(TopicArn = os.environ['SNS_RESULT_ARN'], Message=message)