package common

import (
	"archive/tar"
	"compress/gzip"
	"errors"
	"fmt"
	"io"
	"io/ioutil"
	"os"
	"os/user"
	"path/filepath"
	"time"

	"github.com/cloudfoundry-community/bosh-softlayer-tools/clients"
	"github.com/cloudfoundry-community/bosh-softlayer-tools/config"
)

var (
	TIMEOUT          time.Duration
	POLLING_INTERVAL time.Duration
)

func CreateTarball(tarballFilePath string, filePaths []string) error {
	file, err := os.Create(tarballFilePath)
	if err != nil {
		return errors.New(fmt.Sprintf("Could not create tarball file '%s', got error '%s'", tarballFilePath, err.Error()))
	}
	defer file.Close()

	gzipWriter := gzip.NewWriter(file)
	defer gzipWriter.Close()

	tarWriter := tar.NewWriter(gzipWriter)
	defer tarWriter.Close()

	for _, filePath := range filePaths {
		err := addFileToTarWriter(filePath, tarWriter)
		if err != nil {
			return errors.New(fmt.Sprintf("Could not add file '%s', to tarball, got error '%s'", filePath, err.Error()))
		}
	}

	return nil
}

func ReadJsonTestFixtures(rootPath, packageName, fileName string) ([]byte, error) {
	wd, _ := os.Getwd()
	return ioutil.ReadFile(filepath.Join(wd, rootPath, "test_fixtures", packageName, fileName))
}

func CreateBmpClient() (clients.BmpClient, error) {
	currentUser, err := user.Current()
	if err != nil {
		return nil, err
	}

	c := config.NewConfig(filepath.Join(currentUser.HomeDir, config.CONFIG_FILE_NAME))
	configInfo, err := c.LoadConfig()
	if err != nil {
		return nil, err
	}

	return clients.NewBmpClient(configInfo.Username, configInfo.Password, configInfo.TargetUrl, nil, c.Path()), nil
}

func CreateDefaultConfig() (config.ConfigInfo, error) {
	return CreateConfig("")
}

func CreateConfig(pathToConfig string) (config.ConfigInfo, error) {
	config := config.NewConfig(pathToConfig)
	return config.LoadConfig()
}

// Private methods

func addFileToTarWriter(filePath string, tarWriter *tar.Writer) error {
	file, err := os.Open(filePath)
	if err != nil {
		return errors.New(fmt.Sprintf("Could not open file '%s', got error '%s'", filePath, err.Error()))
	}
	defer file.Close()

	stat, err := file.Stat()
	if err != nil {
		return errors.New(fmt.Sprintf("Could not get stat for file '%s', got error '%s'", filePath, err.Error()))
	}

	header := &tar.Header{
		Name:    filePath,
		Size:    stat.Size(),
		Mode:    int64(stat.Mode()),
		ModTime: stat.ModTime(),
	}

	err = tarWriter.WriteHeader(header)
	if err != nil {
		return errors.New(fmt.Sprintf("Could not write header for file '%s', got error '%s'", filePath, err.Error()))
	}

	_, err = io.Copy(tarWriter, file)
	if err != nil {
		return errors.New(fmt.Sprintf("Could not copy the file '%s' data to the tarball, got error '%s'", filePath, err.Error()))
	}

	return nil
}
