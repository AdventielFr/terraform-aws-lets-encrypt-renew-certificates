import json
import os
import shutil
import boto3
import certbot.main
import logging
import validators

logger = logging.getLogger('adv_lambda')
logger.setLevel(logging.INFO)

# Let’s Encrypt acme-v02 server that supports wildcard certificates
CERTBOT_SERVER =  os.environ["CERTBOT_SERVER_URL"]

# Temp dir of Lambda runtime
CERTBOT_DIR = '/tmp/certbot'

def _rm_tmp_dir():
    logger.info('Clean temporary directories...')
    if os.path.exists(CERTBOT_DIR):
        try:
            shutil.rmtree(CERTBOT_DIR)
        except NotADirectoryError:
            os.remove(CERTBOT_DIR)

def _check_payload(payload):
    logger.info('Check payload....')
    if payload == None:
        raise ValueError("payload is mandatory")
    if 'email' not in payload:
        raise ValueError("payload.email is mandatory")
    if not validators.email(payload['email']):
        raise ValueError("{} is not valid email".format(payload['email']))
    if 'domain' not in payload:
        raise ValueError("payload.domain is mandatory")
    if not validators.domain(payload['domain']):
        raise ValueError("{} is not valid domain".format(payload['domain']))
    logger.info('Payload is ready')

def _obtain_certs(payload):
    logger.info('Obtain certificate....')
    _check_payload(payload)
    certbot_args = [
        # Override directory paths so script doesn't have to be run as root
        '--config-dir', CERTBOT_DIR,
        '--work-dir', CERTBOT_DIR,
        '--logs-dir', CERTBOT_DIR,
        # Obtain a cert but don't install it
        'certonly',
        # Run in non-interactive mode
        '--non-interactive',
        # Agree to the terms of service
        '--agree-tos',
        # Email of domain administrator
        '--email', payload['email'],
        # Use dns challenge with route53
        '--dns-route53',
        '--preferred-challenges', 'dns-01',
        # Use this server instead of default acme-v01
        '--server', CERTBOT_SERVER,
        '-d', payload['domain']
    ]
    return certbot.main.main(certbot_args)

def _upload_certs(payload, s3_bucket, s3_prefix):
    client = boto3.client('s3')
    result = {}
    cert_dir = os.path.join(CERTBOT_DIR, 'live')
    for dirpath, _dirnames, filenames in os.walk(cert_dir):
        for filename in filenames:
            local_path = os.path.join(dirpath, filename)
            relative_path = os.path.relpath(local_path, cert_dir)
            s3_key = os.path.join(s3_prefix, relative_path)
            logger.info('Uploading: {} => s3://{}/{}'.format(local_path,s3_bucket,s3_key))
            client.upload_file(local_path, s3_bucket, s3_key)
            if local_path.endswith('privkey.pem'):
                result['PrivateKey'] = get_bytes_from_file(local_path)
                logger.info('Private Key: {}'.format(result['PrivateKey']))
            if local_path.endswith('fullchain.pem'):
                result['CertificateChain'] = get_bytes_from_file(local_path)
                logger.info('Certificate Chain: {}'.format(result['CertificateChain']))
            if local_path.endswith('cert.pem'): 
                 result['Certificate'] = get_bytes_from_file(local_path)
                 logger.info('Certificate: {}'.format(result['Certificate']))
    return result
                
def _find_certificate_arn(client, payload):
    response = client.list_certificates()
    if 'CertificateSummaryList' in response:
        for item in response['CertificateSummaryList']:
            if item['DomainName'] == payload['domain']:
                return item['CertificateArn']
    return None

def _create_or_update_cert(payload, info):
    client = boto3.client('acm')
    certificateArn = _find_certificate_arn(client, payload)
    response = None
    if(certificateArn == None):
        logger.info('Update Certificate : {}'.format(payload['domain']))
        response = client.import_certificate(
            Certificate = info['Certificate'], 
            PrivateKey = info['PrivateKey'], 
            CertificateChain = info['CertificateChain']
        )
    else:
        logger.info('Create Certificate : {}'.format(payload['domain']))
        response = client.import_certificate(
            CertificateArn = certificateArn, 
            Certificate = info['Certificate'], 
            PrivateKey = info['PrivateKey'], 
            CertificateChain = info['CertificateChain']
        )
    certificateArn = response['CertificateArn']
    response = client.add_tags_to_certificate(
        CertificateArn=certificateArn,
        Tags=[
            {
                'Key': 'Name',
                'Value': payload['domain']
            },{
                'Key': 'Email',
                'Value': payload['email']
            },{
                'Key': 'Origin',
                'Value': 'Let''s Encrypt'
            }
        ]
    )

def _guarded_handler(event, context):
 
    s3_bucket = os.environ['S3_BUCKET']
    s3_prefix = "live"
    payload = None
    for record in event['Records']:
        body = record["body"]
        payload = json.loads(body.replace('\'','"'))
        logger.info(payload)
        result = _obtain_certs(payload)
        info = _upload_certs(payload, s3_bucket, s3_prefix)
        _create_or_update_cert(payload, info)
    return payload
 
def _send_message(message):
    logger.info('Send result message ....')
    sns = boto3.client('sns')
    return sns.publish(TopicArn = os.environ['SNS_RESULT_ARN'], Message=message)

def lambda_handler(event, context):
    try:
        _rm_tmp_dir()
        payload = _guarded_handler(event, context)
        logger.info('Certificate obtained and uploaded successfully.')
        _send_message("Certificate obtained and uploaded successfully for {}".format(payload['domain']))
    except Exception as e:
        logger.error(e)
        _send_message("Fail to renew certificates from let's and script reason: {}".format(e))
    finally:
        _rm_tmp_dir()
