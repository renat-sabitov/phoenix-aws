import os
from os import errno
import json
from logger import Logger
import boto, boto.s3
from boto.s3.key import Key

class GCR(object):
    CACHE = '/tmp/gcr'
    BUCKET_NAME='/etc/sysconfig/gcr-bucket'
    def __init__(self, log = None):
        self._logger = log or Logger.create('GCR')
        self.__bucket_name = None
        self._cache = {}

    def get(self, key):
        value = self._read_key(key)
        # This should load the config from S3
        try:
            self._logger.debug("GCR.get('%s') returned '%s'" % (key, value))
            return json.loads(value)
        except ValueError, e:
            msg = "Failed to parse GCR config %s from '%s' [%s]" % (key, value, str(e))
            self._logger.error(msg)
            raise Exception(msg)

    def _write_cache(self, key, value):
        try:
            with open(os.path.join(GCR.CACHE, key), 'w') as cache:
                self._logger.debug("Writing to cache %s, value: '%s'" % (key, value))
                self._cache[key] = value.strip()
                cache.write(value.strip())
        except IOError, e:
            if e.errno == errno.ENOENT and not os.path.exists(GCR.CACHE):
                self._logger.debug("Making %s as it doesn't exist" % (GCR.CACHE))
                os.makedirs(GCR.CACHE)
                self._write_cache(key, value)
            else:
                self._logger.info("Failed to write to cache %s, continuing.. (%s)" % (os.path.join(GCR.CACHE, key), e.errno))
            pass

    def _read_cache(self, key):
        if key in self._cache:
            return self._cache[key]

        try:
            with open(os.path.join(GCR.CACHE, key), 'r') as cache:
                self._cache[key] = cache.read().strip()
                return self._cache[key]
        except IOError, e:
            # Key hasn't been loaded into this EC2 instance yet, keep going.
            pass
        return None

    @property
    def _bucket_name(self):
        # Make sure we know where the remote server is
        if self.__bucket_name == None:
            self._logger.debug("opening %s to read bucket name" % (GCR.BUCKET_NAME))
            try:
                with open(GCR.BUCKET_NAME, 'r') as config:
                    self.__bucket_name = config.read().strip()
                    self._logger.info("using bucket %s for GCR" % (self.__bucket_name))
            except IOError, e:
                msg = "Failed to load config from '%s' [%s]" % (GCR.BUCKET_NAME, e.strerror)
                self._logger.error(msg)
                raise Exception(msg)
        return self.__bucket_name

    def _get_s3(self, resource):
        self._logger.debug("loading config from s3:://%s/%s" %(self._bucket_name, resource))
        conn = boto.connect_s3()
        bucket = conn.get_bucket(self._bucket_name)
        key = Key(bucket)
        key.key = resource
        value = key.get_contents_as_string()
        return value.strip()

    def _read_key(self, key):
        value = self._read_cache(key)
        if value is not None: return value
        value = self._get_s3(key)
        self._write_cache(key, value)
        return value

