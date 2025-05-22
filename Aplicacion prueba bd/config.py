import os
from datetime import timedelta


class Config:
    """Configuración base de la aplicación"""

    # Configuración de Flask
    SECRET_KEY = os.environ.get('SECRET_KEY') or 'dev-secret-key-change-in-production'
    DEBUG = os.environ.get('FLASK_DEBUG', 'False').lower() == 'true'

    # Configuración de la base de datos
    DB_HOST = os.environ.get('DB_HOST', 'localhost')
    DB_NAME = os.environ.get('DB_NAME', 'clinica_veterinaria_altavida')
    DB_USER = os.environ.get('DB_USER', 'root')
    DB_PASSWORD = os.environ.get('DB_PASSWORD', '')
    DB_CHARSET = 'utf8mb4'

    # Configuración de sesiones
    PERMANENT_SESSION_LIFETIME = timedelta(hours=2)

    # Configuración JSON
    JSON_AS_ASCII = False
    JSON_SORT_KEYS = True
    JSONIFY_PRETTYPRINT_REGULAR = True

    @property
    def db_config(self):
        """Retorna la configuración de la base de datos"""
        return {
            'host': self.DB_HOST,
            'database': self.DB_NAME,
            'user': self.DB_USER,
            'password': self.DB_PASSWORD,
            'charset': self.DB_CHARSET,
            'autocommit': False,
            'use_unicode': True
        }


class DevelopmentConfig(Config):
    """Configuración para desarrollo"""
    DEBUG = True


class ProductionConfig(Config):
    """Configuración para producción"""
    DEBUG = False


class TestingConfig(Config):
    """Configuración para testing"""
    TESTING = True
    DB_NAME = 'clinica_veterinaria_test'


# Diccionario de configuraciones
config = {
    'development': DevelopmentConfig,
    'production': ProductionConfig,
    'testing': TestingConfig,
    'default': DevelopmentConfig
}