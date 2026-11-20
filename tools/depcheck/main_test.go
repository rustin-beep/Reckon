package main

import (
	"reflect"
	"testing"
)

func TestDepsFromManifest(t *testing.T) {
	cases := []struct {
		name string
		src  string
		want []string
	}{
		{
			name: "没有 import",
			src:  "name = \"vitro/reckon\"\nversion = \"0.1.0\"\n",
			want: nil,
		},
		{
			name: "块形式",
			src:  "name = \"a/b\"\n\nimport {\n  \"moonbitlang/x@0.4.6\",\n  \"moonbit-community/foo\",\n}\n",
			want: []string{"moonbitlang/x@0.4.6", "moonbit-community/foo"},
		},
		{
			name: "单行形式",
			src:  "import { \"moonbitlang/x\" }\n",
			want: []string{"moonbitlang/x"},
		},
		{
			// 评审 P2-1：`import` 与 `{` 分行时，按行匹配会漏报，MoonBit 却照常解析。
			name: "import 与花括号分行",
			src:  "name = \"a/b\"\nimport\n{\n  \"evil/pkg\",\n}\n",
			want: []string{"evil/pkg"},
		},
		{
			name: "路径依赖只取模块名",
			src:  "import {\n  \"vitro/local\": { path = \"../local\" },\n}\n",
			want: []string{"vitro/local"},
		},
		{
			name: "字符串里的 import 不算",
			src:  "name = \"a/b\"\ndescription = \"import { \\\"evil/pkg\\\" }\"\n",
			want: nil,
		},
		{
			name: "注释被跳过",
			src:  "# import { \"evil/comment\" }\nimport {\n  # \"evil/inline\"\n  \"moonbitlang/x\",\n}\n",
			want: []string{"moonbitlang/x"},
		},
		{
			name: "多个 import 块",
			src:  "import { \"moonbitlang/a\" }\nimport\n{\n  \"moonbitlang/b\",\n}\n",
			want: []string{"moonbitlang/a", "moonbitlang/b"},
		},
		{
			name: "标识符前缀不算 import",
			src:  "imports = \"x\"\n",
			want: nil,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := depsFromManifest(tc.src)
			if !reflect.DeepEqual(got, tc.want) {
				t.Fatalf("depsFromManifest() = %#v, want %#v", got, tc.want)
			}
		})
	}
}

func TestForbidden(t *testing.T) {
	cases := []struct {
		name string
		deps []string
		want []string
	}{
		{
			name: "允许的命名空间",
			deps: []string{"moonbitlang/x@0.4.6", "moonbit-community/abc"},
			want: nil,
		},
		{
			name: "第三方",
			deps: []string{"caimeox/evmasm"},
			want: []string{"caimeox/evmasm"},
		},
		{
			name: "官方成员的个人包仍算第三方",
			deps: []string{"moonbitlang/x", "someone/thing"},
			want: []string{"someone/thing"},
		},
		{
			name: "前缀必须是命名空间而不是子串",
			deps: []string{"moonbitlangx/foo", "moonbit-communityx/foo"},
			want: []string{"moonbitlangx/foo", "moonbit-communityx/foo"},
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := forbidden(tc.deps)
			if !reflect.DeepEqual(got, tc.want) {
				t.Fatalf("forbidden() = %#v, want %#v", got, tc.want)
			}
		})
	}
}
