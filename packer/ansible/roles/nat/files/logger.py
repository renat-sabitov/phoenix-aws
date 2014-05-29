import logging, logging.handlers

class Logger(object):
    @staticmethod
    def create(name, debug=False):
        ''' Configure a logger to send messages to SysLog.  '''
        logger = logging.getLogger(name)
        logger.setLevel(logging.INFO)
        handler = logging.handlers.SysLogHandler(address="/dev/log",
            facility=logging.handlers.SysLogHandler.LOG_LOCAL6)
        formatter = logging.Formatter('%(filename)s: %(levelname)s: %(message)s')
        handler.setFormatter(formatter)
        logger.addHandler(handler)

        if debug == True:
            stream = logging.StreamHandler()
            stream.setLevel(logging.DEBUG)
            logger.setLevel(logging.DEBUG)
            formatter = logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")
            stream.setFormatter(formatter)
            logger.addHandler(stream)
        return logger



